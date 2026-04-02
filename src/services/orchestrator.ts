/**
 * Deployment Orchestrator
 * Coordinates all services to deploy artifacts
 */
import { join } from 'path';
import { homedir } from 'os';
import { existsSync, mkdirSync, writeFileSync, readFileSync } from 'fs';
import type { 
  ArtifactConfig, 
  Deployment, 
  UActionsConfig,
  WatcherEventType 
} from '../types';
import { DeploymentStatus } from '../types';
import { generateDomain, generateContainerName, generateInternalPort } from '../utils/artifact';
import { DomainManager } from './domain-manager';
import { PodmanManager } from './podman-manager';
import { TraefikManager } from './traefik-manager';
import { UActionsWatcher } from './watcher';
import { GitHubManager } from './github-manager';
import { getLogger } from '../utils/logger';

const logger = getLogger();

export interface OrchestratorOptions {
  verbose?: boolean;
  autoPR?: boolean;
}

export class DeploymentOrchestrator {
  private config: UActionsConfig;
  private domainManager: DomainManager;
  private podmanManager: PodmanManager;
  private traefikManager: TraefikManager;
  private watcher: UActionsWatcher;
  private githubManager: GitHubManager;
  private deployments: Map<string, Deployment> = new Map();
  private configPath: string;

  constructor(config?: UActionsConfig) {
    this.configPath = join(homedir(), '.uactions', 'config.json');
    this.config = config || this.loadConfig();
    
    this.domainManager = new DomainManager(this.config);
    this.podmanManager = new PodmanManager(join(homedir(), '.uactions', 'temp'));
    this.traefikManager = new TraefikManager(this.config);
    this.watcher = new UActionsWatcher(this.config.uactionsPath);
    this.githubManager = new GitHubManager();
    
    // Setup watcher callback
    this.watcher.onEvent(this.handleWatcherEvent.bind(this));
  }

  /**
   * Load configuration from file
   */
  private loadConfig(): UActionsConfig {
    try {
      if (existsSync(this.configPath)) {
        const content = readFileSync(this.configPath, 'utf-8');
        return JSON.parse(content);
      }
    } catch {
      // Ignore errors
    }
    
    // Return default config
    return {
      installId: this.generateInstallId(),
      baseDomain: DomainManager.generateBaseDomain(),
      publicEnabled: false,
      uactionsPath: join(homedir(), 'uactions'),
      traefik: {
        enabled: true,
        version: 'v3.5.4',
        acmeEmail: undefined,
        dashboardEnabled: true,
      },
      podman: {
        useRootless: true,
      },
      initialized: false,
    };
  }

  /**
   * Save configuration
   */
  saveConfig(): void {
    const configDir = join(homedir(), '.uactions');
    if (!existsSync(configDir)) {
      mkdirSync(configDir, { recursive: true });
    }
    writeFileSync(this.configPath, JSON.stringify(this.config, null, 2));
  }

  /**
   * Generate unique install ID
   */
  private generateInstallId(): string {
    return `ua-${Date.now()}-${Math.random().toString(36).substr(2, 9)}`;
  }

  /**
   * Handle watcher events
   */
  private async handleWatcherEvent(event: { 
    type: WatcherEventType; 
    path: string; 
    artifact?: ArtifactConfig 
  }): Promise<void> {
    if (event.type === 'deleted') {
      // Find and stop deployment for this path
      for (const [id, deployment] of this.deployments.entries()) {
        if (deployment.artifactName === event.path.split('/').pop()) {
          await this.stopDeployment(id);
          break;
        }
      }
      return;
    }

    if (event.artifact) {
      await this.deployArtifact(event.artifact);
    }
  }

  /**
   * Initialize the system (first run)
   */
  async initialize(options: { 
    baseDomain?: string; 
    publicEnabled?: boolean;
    acmeEmail?: string;
  } = {}): Promise<void> {
    logger.banner('UActions Initialization');

    // Update config with options
    if (options.baseDomain) {
      this.config.baseDomain = options.baseDomain;
    }
    if (options.publicEnabled !== undefined) {
      this.config.publicEnabled = options.publicEnabled;
    }
    if (options.acmeEmail) {
      this.config.traefik.acmeEmail = options.acmeEmail;
    }

    // Check prerequisites
    if (!this.podmanManager.isInstalled()) {
      logger.error('Podman is not installed. Please install Podman first.');
      logger.info('macOS: brew install podman');
      logger.info('Linux: sudo apt-get install podman');
      throw new Error('Podman not installed');
    }

    logger.success(`Podman detected: ${this.podmanManager.getVersion()}`);

    // Create uactions directory
    if (!existsSync(this.config.uactionsPath)) {
      mkdirSync(this.config.uactionsPath, { recursive: true });
      logger.success(`Created uactions directory: ${this.config.uactionsPath}`);
    }

    // Start Traefik
    logger.section('Starting Traefik');
    await this.traefikManager.pullImage();
    await this.traefikManager.start();

    // Mark as initialized
    this.config.initialized = true;
    this.saveConfig();

    logger.banner('Initialization Complete');
    logger.info(`Base domain: ${this.config.baseDomain}`);
    logger.info(`UActions path: ${this.config.uactionsPath}`);
    logger.info(`Traefik dashboard: http://localhost:8080`);
    logger.info('');
    logger.info('Create your first deployment by adding an artifact.json to:');
    logger.info(`  ${this.config.uactionsPath}/<your-project>/artifact.json`);
  }

  /**
   * Deploy an artifact
   */
  async deployArtifact(artifact: ArtifactConfig): Promise<Deployment> {
    const deploymentId = `deploy-${Date.now()}-${artifact.name}`;
    const fullDomain = generateDomain(artifact, this.config.baseDomain);

    logger.banner(`Deploying: ${artifact.name}`);
    logger.info(`Domain: ${fullDomain}`);
    logger.info(`Source: ${artifact.source.url}`);

    // Create deployment record
    let deployment: Deployment = {
      id: deploymentId,
      artifactName: artifact.name,
      domain: fullDomain,
      status: DeploymentStatus.PENDING,
      createdAt: new Date(),
      updatedAt: new Date(),
      urls: {
        local: `http://${fullDomain}`,
      },
    };

    this.deployments.set(deploymentId, deployment);

    try {
      // Add domain to hosts file
      const internalPort = generateInternalPort(artifact);
      await this.domainManager.addDomain(
        artifact.domain.subdomain,
        internalPort,
        deploymentId
      );

      // Pull source
      deployment.status = DeploymentStatus.PULLING;
      const sourceDir = await this.podmanManager.pullSource(artifact, deploymentId);

      // Build image
      deployment.status = DeploymentStatus.BUILDING;
      const imageName = await this.podmanManager.buildImage(artifact, sourceDir, deploymentId);

      // Run container
      deployment.status = DeploymentStatus.DEPLOYING;
      const containerDeployment = await this.podmanManager.runContainer(
        artifact,
        imageName,
        deploymentId,
        this.config.baseDomain
      );

      // Update deployment
      deployment = {
        ...deployment,
        status: DeploymentStatus.RUNNING,
        containerId: containerDeployment.containerId,
        port: internalPort,
        updatedAt: new Date(),
      };

      this.deployments.set(deploymentId, deployment);

      logger.success(`Deployment successful!`);
      logger.info(`URL: http://${fullDomain}`);

      // Create GitHub PR if configured
      if (artifact.github?.autoPR && this.githubManager.isAuthenticated()) {
        await this.githubManager.createArtifactPR(
          artifact,
          sourceDir,
          this.detectProjectType(artifact)
        );
      }

      return deployment;
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      logger.error(`Deployment failed: ${message}`);
      
      deployment.status = DeploymentStatus.ERROR;
      deployment.error = message;
      deployment.updatedAt = new Date();
      this.deployments.set(deploymentId, deployment);

      throw error;
    }
  }

  /**
   * Detect project type from artifact
   */
  private detectProjectType(artifact: ArtifactConfig): 'php-laravel' | 'node' | 'static' | 'python' {
    const url = artifact.source.url.toLowerCase();
    
    if (url.includes('laravel') || url.includes('php')) {
      return 'php-laravel';
    }
    if (url.includes('node') || url.includes('npm') || url.includes('javascript')) {
      return 'node';
    }
    if (url.includes('python') || url.includes('flask') || url.includes('django')) {
      return 'python';
    }
    
    return 'static';
  }

  /**
   * Stop a deployment
   */
  async stopDeployment(id: string): Promise<boolean> {
    const deployment = this.deployments.get(id);
    if (!deployment) {
      logger.warn(`Deployment ${id} not found`);
      return false;
    }

    logger.info(`Stopping deployment: ${deployment.artifactName}`);

    try {
      // Remove container
      const containerName = generateContainerName({ 
        name: deployment.artifactName, 
        domain: { subdomain: deployment.domain.split('.')[0] } 
      } as ArtifactConfig);
      
      this.podmanManager.stopContainer(containerName);
      this.podmanManager.removeContainer(containerName);

      // Remove domain
      await this.domainManager.removeDomain(deployment.domain.split('.')[0]);

      // Update deployment
      deployment.status = DeploymentStatus.STOPPED;
      deployment.updatedAt = new Date();
      this.deployments.set(id, deployment);

      logger.success(`Deployment stopped: ${deployment.artifactName}`);
      return true;
    } catch (error) {
      logger.error(`Failed to stop deployment: ${error}`);
      return false;
    }
  }

  /**
   * Start the watcher
   */
  async startWatcher(): Promise<void> {
    await this.watcher.start();
    
    // Deploy existing artifacts
    const existing = await this.watcher.scanExisting();
    for (const artifact of existing) {
      logger.info(`Found existing artifact: ${artifact.name}`);
      await this.deployArtifact(artifact);
    }
  }

  /**
   * Stop the watcher
   */
  async stopWatcher(): Promise<void> {
    await this.watcher.stop();
  }

  /**
   * List all deployments
   */
  listDeployments(): Deployment[] {
    return Array.from(this.deployments.values());
  }

  /**
   * Get deployment by ID
   */
  getDeployment(id: string): Deployment | undefined {
    return this.deployments.get(id);
  }

  /**
   * Get system status
   */
  getStatus(): {
    initialized: boolean;
    baseDomain: string;
    podmanInstalled: boolean;
    traefikRunning: boolean;
    deployments: number;
    watcherRunning: boolean;
  } {
    return {
      initialized: this.config.initialized,
      baseDomain: this.config.baseDomain,
      podmanInstalled: this.podmanManager.isInstalled(),
      traefikRunning: this.traefikManager.isRunning(),
      deployments: this.deployments.size,
      watcherRunning: this.watcher.isRunning(),
    };
  }

  /**
   * Cleanup everything
   */
  async cleanup(): Promise<void> {
    logger.banner('Cleaning up UActions');

    // Stop watcher
    await this.stopWatcher();

    // Stop all deployments
    for (const [id] of this.deployments) {
      await this.stopDeployment(id);
    }

    // Stop Traefik
    this.traefikManager.stop();

    // Cleanup domains
    await this.domainManager.cleanup();

    // Cleanup temp files
    this.podmanManager.cleanup();

    logger.success('Cleanup complete');
  }
}
