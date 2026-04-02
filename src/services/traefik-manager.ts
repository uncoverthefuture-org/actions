/**
 * Traefik Manager
 * Sets up and manages Traefik reverse proxy locally
 * Based on setup-traefik.sh from uactions
 */
import { execSync } from 'child_process';
import { existsSync, mkdirSync, writeFileSync, unlinkSync } from 'fs';
import { join } from 'path';
import { homedir } from 'os';
import type { UActionsConfig } from '../types';
import { getLogger } from '../utils/logger';

const logger = getLogger();

export interface TraefikStatus {
  running: boolean;
  version?: string;
  containerId?: string;
  ports?: string[];
  dashboardUrl?: string;
}

export class TraefikManager {
  private config: UActionsConfig;
  private configDir: string;
  private dataDir: string;
  private traefikYmlPath: string;
  private acmeJsonPath: string;

  constructor(config: UActionsConfig) {
    this.config = config;
    this.configDir = join(homedir(), '.uactions', 'traefik');
    this.dataDir = join(homedir(), '.uactions', 'traefik', 'data');
    this.traefikYmlPath = join(this.configDir, 'traefik.yml');
    this.acmeJsonPath = join(this.dataDir, 'acme.json');
    
    this.ensureDirectories();
  }

  /**
   * Ensure config directories exist
   */
  private ensureDirectories(): void {
    if (!existsSync(this.configDir)) {
      mkdirSync(this.configDir, { recursive: true });
    }
    if (!existsSync(this.dataDir)) {
      mkdirSync(this.dataDir, { recursive: true });
    }
  }

  /**
   * Check if Traefik is running
   */
  isRunning(): boolean {
    try {
      execSync('podman container exists uactions-traefik', { stdio: 'pipe' });
      const status = execSync(
        'podman inspect -f "{{.State.Status}}" uactions-traefik',
        { encoding: 'utf-8', stdio: 'pipe' }
      );
      return status.trim() === 'running';
    } catch {
      return false;
    }
  }

  /**
   * Get Traefik status
   */
  getStatus(): TraefikStatus {
    try {
      if (!this.isRunning()) {
        return { running: false };
      }

      const output = execSync(
        'podman inspect uactions-traefik --format "{{.Id}}|{{.NetworkSettings.Ports}}"',
        { encoding: 'utf-8', stdio: 'pipe' }
      );
      
      const [containerId] = output.trim().split('|');
      const dashboardUrl = this.config.traefik.dashboardEnabled 
        ? 'http://localhost:8080'
        : undefined;

      return {
        running: true,
        version: this.config.traefik.version,
        containerId: containerId?.slice(0, 12),
        dashboardUrl,
      };
    } catch {
      return { running: false };
    }
  }

  /**
   * Generate traefik.yml configuration
   */
  private generateConfig(): string {
    const useAcme = this.config.traefik.acmeEmail ? true : false;
    
    const providersSection = `
providers:
  docker:
    exposedByDefault: false
    endpoint: "unix:///var/run/docker.sock"
    watch: true
  file:
    directory: /etc/traefik/dynamic
    watch: true
`;

    const entrypointsSection = `
entryPoints:
  web:
    address: ":80"
  websecure:
    address: ":443"
`;

    const apiSection = `
api:
  dashboard: ${this.config.traefik.dashboardEnabled}
  insecure: ${this.config.traefik.dashboardEnabled}
`;

    const pingSection = `
ping:
  entryPoint: "web"
`;

    const logSection = `
log:
  level: INFO
`;

    const acmeSection = useAcme ? `
certificatesResolvers:
  letsencrypt:
    acme:
      email: "${this.config.traefik.acmeEmail}"
      storage: "/letsencrypt/acme.json"
      tlsChallenge: {}
` : '';

    return `global:
  checkNewVersion: false
  sendAnonymousUsage: false

${entrypointsSection}
${providersSection}
${apiSection}
${pingSection}
${logSection}
${acmeSection}
`;
  }

  /**
   * Start Traefik
   */
  async start(): Promise<boolean> {
    if (this.isRunning()) {
      logger.info('Traefik is already running');
      return true;
    }

    // Write configuration
    const config = this.generateConfig();
    writeFileSync(this.traefikYmlPath, config);
    
    // Ensure acme.json exists and has correct permissions
    if (!existsSync(this.acmeJsonPath)) {
      writeFileSync(this.acmeJsonPath, '{}');
    }
    try {
      execSync(`chmod 600 "${this.acmeJsonPath}"`, { stdio: 'pipe' });
    } catch {
      // Ignore permission errors
    }

    // Check for port conflicts
    if (this.hasPortConflict(80) || this.hasPortConflict(443)) {
      logger.error('Ports 80 or 443 are already in use. Please stop conflicting services.');
      return false;
    }

    // Check for dashboard port
    if (this.config.traefik.dashboardEnabled && this.hasPortConflict(8080)) {
      logger.warn('Port 8080 is in use. Dashboard may not be accessible.');
    }

    logger.info('Starting Traefik...');

    try {
      // Create network if it doesn't exist
      try {
        execSync('podman network exists traefik-network', { stdio: 'pipe' });
      } catch {
        execSync('podman network create traefik-network', { stdio: 'pipe' });
        logger.success('Created traefik-network');
      }

      // Start Traefik container
      const runArgs = [
        'run', '-d',
        '--name', 'uactions-traefik',
        '--restart', 'unless-stopped',
        '-p', '80:80',
        '-p', '443:443',
      ];

      if (this.config.traefik.dashboardEnabled) {
        runArgs.push('-p', '8080:8080');
      }

      runArgs.push(
        '-v', `${this.traefikYmlPath}:/etc/traefik/traefik.yml:ro`,
        '-v', `${this.dataDir}:/letsencrypt`,
        '-v', '/var/run/docker.sock:/var/run/docker.sock:ro',
        '--network', 'traefik-network',
        `docker.io/traefik:${this.config.traefik.version}`
      );

      execSync(`podman ${runArgs.join(' ')}`, { stdio: 'inherit' });

      // Wait for Traefik to be ready
      await this.waitForReady();

      logger.success('Traefik started successfully');
      
      if (this.config.traefik.dashboardEnabled) {
        logger.info('Dashboard available at http://localhost:8080');
      }

      return true;
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      logger.error(`Failed to start Traefik: ${message}`);
      return false;
    }
  }

  /**
   * Stop Traefik
   */
  stop(): boolean {
    try {
      execSync('podman stop uactions-traefik 2>/dev/null || true', { stdio: 'pipe' });
      execSync('podman rm uactions-traefik 2>/dev/null || true', { stdio: 'pipe' });
      logger.success('Traefik stopped');
      return true;
    } catch {
      return false;
    }
  }

  /**
   * Restart Traefik
   */
  async restart(): Promise<boolean> {
    this.stop();
    return this.start();
  }

  /**
   * Check if a port is in use
   */
  private hasPortConflict(port: number): boolean {
    try {
      // Try to check if port is in use
      execSync(`lsof -Pi :${port} -sTCP:LISTEN -t 2>/dev/null || netstat -tuln 2>/dev/null | grep :${port}`, { stdio: 'pipe' });
      return true;
    } catch {
      return false;
    }
  }

  /**
   * Wait for Traefik to be ready
   */
  private async waitForReady(): Promise<void> {
    const maxAttempts = 30;
    const delay = 1000;

    for (let i = 0; i < maxAttempts; i++) {
      try {
        // Check if container is running
        const status = execSync(
          'podman inspect -f "{{.State.Status}}" uactions-traefik',
          { encoding: 'utf-8', stdio: 'pipe' }
        );
        
        if (status.trim() === 'running') {
          // Try to ping Traefik
          try {
            execSync('curl -s http://localhost:80/ping', { stdio: 'pipe', timeout: 5000 });
            return;
          } catch {
            // Not ready yet
          }
        }
      } catch {
        // Container not ready
      }
      
      await new Promise(resolve => setTimeout(resolve, delay));
    }
    
    throw new Error('Traefik did not become ready in time');
  }

  /**
   * Get Traefik logs
   */
  getLogs(tail: number = 50): string {
    try {
      return execSync(
        `podman logs --tail=${tail} uactions-traefik 2>&1`,
        { encoding: 'utf-8', stdio: 'pipe' }
      );
    } catch {
      return 'No logs available';
    }
  }

  /**
   * Check if Traefik is installed (Podman has the image)
   */
  isInstalled(): boolean {
    try {
      const output = execSync(
        `podman images docker.io/traefik:${this.config.traefik.version} --format "{{.Repository}}"`,
        { encoding: 'utf-8', stdio: 'pipe' }
      );
      return output.includes('traefik');
    } catch {
      return false;
    }
  }

  /**
   * Pull Traefik image
   */
  async pullImage(): Promise<boolean> {
    try {
      logger.info(`Pulling Traefik image v${this.config.traefik.version}...`);
      execSync(`podman pull docker.io/traefik:${this.config.traefik.version}`, { stdio: 'inherit' });
      return true;
    } catch (error) {
      logger.error(`Failed to pull Traefik image: ${error}`);
      return false;
    }
  }

  /**
   * Cleanup Traefik configuration and data
   */
  cleanup(): void {
    this.stop();
    
    try {
      if (existsSync(this.configDir)) {
        // Keep acme.json but remove other configs
        const files = execSync(`ls -1 "${this.configDir}"`, { encoding: 'utf-8', stdio: 'pipe' }).split('\n');
        for (const file of files) {
          if (file && file !== 'acme.json' && file !== 'data') {
            try {
              unlinkSync(join(this.configDir, file));
            } catch {
              // Ignore
            }
          }
        }
      }
      logger.success('Traefik configuration cleaned up');
    } catch {
      // Ignore cleanup errors
    }
  }
}
