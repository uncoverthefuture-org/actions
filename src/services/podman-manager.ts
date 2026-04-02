/**
 * Podman Container Manager
 * Handles container lifecycle: build, run, stop, remove
 * Inspired by ssh-container-deploy scripts
 */
import { execSync } from 'child_process';
import { existsSync, mkdirSync, writeFileSync, rmSync } from 'fs';
import { join } from 'path';
import type { ArtifactConfig, Deployment } from '../types';
import { DeploymentStatus } from '../types';
import { generateContainerName, generateInternalPort } from '../utils/artifact';
import { getLogger } from '../utils/logger';

const logger = getLogger();

export interface ContainerInfo {
  id: string;
  name: string;
  status: string;
  ports: string;
  image: string;
}

export class PodmanManager {
  private tempDir: string;
  private deployments: Map<string, Deployment> = new Map();

  constructor(tempDir: string = '/tmp/uactions') {
    this.tempDir = tempDir;
    this.ensureTempDir();
  }

  /**
   * Ensure temp directory exists
   */
  private ensureTempDir(): void {
    if (!existsSync(this.tempDir)) {
      mkdirSync(this.tempDir, { recursive: true });
    }
  }

  /**
   * Check if Podman is installed
   */
  isInstalled(): boolean {
    try {
      execSync('which podman', { stdio: 'pipe' });
      return true;
    } catch {
      return false;
    }
  }

  /**
   * Get Podman version
   */
  getVersion(): string {
    try {
      const output = execSync('podman --version', { encoding: 'utf-8', stdio: 'pipe' });
      return output.trim();
    } catch {
      return 'unknown';
    }
  }

  /**
   * Check if container exists
   */
  containerExists(name: string): boolean {
    try {
      execSync(`podman container exists "${name}"`, { stdio: 'pipe' });
      return true;
    } catch {
      return false;
    }
  }

  /**
   * Get container info
   */
  getContainer(name: string): ContainerInfo | null {
    try {
      const output = execSync(
        `podman ps -a --filter "name=${name}" --format "{{.ID}}|{{.Names}}|{{.Status}}|{{.Ports}}|{{.Image}}"`,
        { encoding: 'utf-8', stdio: 'pipe' }
      );
      
      if (!output.trim()) return null;
      
      const [id, containerName, status, ports, image] = output.trim().split('|');
      return { id, name: containerName, status, ports, image };
    } catch {
      return null;
    }
  }

  /**
   * Pull source code from URL
   */
  async pullSource(artifact: ArtifactConfig, deploymentId: string): Promise<string> {
    const sourceDir = join(this.tempDir, deploymentId, 'source');
    
    // Clean up if exists
    if (existsSync(sourceDir)) {
      rmSync(sourceDir, { recursive: true, force: true });
    }
    
    mkdirSync(sourceDir, { recursive: true });

    const { url, ref = 'main' } = artifact.source;

    logger.info(`Pulling source from ${url}...`);

    try {
      if (url.endsWith('.git') || url.includes('github.com') || url.includes('gitlab.com')) {
        // Git repository
        const cloneCmd = `git clone --depth 1 ${ref !== 'main' ? `-b ${ref}` : ''} "${url}" "${sourceDir}"`;
        execSync(cloneCmd, { stdio: 'pipe' });
      } else if (url.endsWith('.tar.gz') || url.endsWith('.tgz')) {
        // Tarball
        const downloadCmd = `curl -L "${url}" | tar -xz -C "${sourceDir}" --strip-components=1`;
        execSync(downloadCmd, { stdio: 'pipe' });
      } else {
        // Try git clone anyway
        execSync(`git clone --depth 1 "${url}" "${sourceDir}"`, { stdio: 'pipe' });
      }

      logger.success(`Source pulled to ${sourceDir}`);
      return sourceDir;
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      throw new Error(`Failed to pull source: ${message}`);
    }
  }

  /**
   * Build container image
   */
  async buildImage(
    artifact: ArtifactConfig, 
    sourceDir: string, 
    deploymentId: string
  ): Promise<string> {
    const imageName = `uactions/${deploymentId}:latest`;
    const dockerfilePath = artifact.container.dockerfile || './Dockerfile';
    const fullDockerfilePath = join(sourceDir, dockerfilePath);

    // Check if Dockerfile exists, if not generate a default one
    if (!existsSync(fullDockerfilePath)) {
      logger.warn(`No Dockerfile found at ${dockerfilePath}, generating default...`);
      const defaultDockerfile = this.generateDefaultDockerfile(artifact);
      writeFileSync(join(sourceDir, 'Dockerfile'), defaultDockerfile);
    }

    const context = artifact.container.context || '.';
    const buildContext = join(sourceDir, context);

    // Build args
    const buildArgs = Object.entries(artifact.build?.args || {})
      .map(([key, value]) => `--build-arg ${key}="${value}"`)
      .join(' ');

    logger.info(`Building image ${imageName}...`);

    try {
      const buildCmd = `podman build -t "${imageName}" -f "${fullDockerfilePath}" ${buildArgs} "${buildContext}"`;
      execSync(buildCmd, { stdio: 'inherit' });
      
      logger.success(`Image built: ${imageName}`);
      return imageName;
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      throw new Error(`Failed to build image: ${message}`);
    }
  }

  /**
   * Generate a default Dockerfile based on project type
   */
  private generateDefaultDockerfile(artifact: ArtifactConfig): string {
    const port = artifact.container.port || 8080;
    
    // Simple nginx-based Dockerfile for static sites
    return `# Generated by UActions
FROM nginx:alpine

# Copy source to nginx html directory
COPY . /usr/share/nginx/html

# Create a simple nginx config that listens on the container port
RUN echo 'server { \\
    listen ${port}; \\
    server_name localhost; \\
    root /usr/share/nginx/html; \\
    index index.html index.htm; \\
    location / { \\
        try_files \$uri \$uri/ /index.html; \\
    } \\
}' > /etc/nginx/conf.d/default.conf

EXPOSE ${port}

CMD ["nginx", "-g", "daemon off;"]
`;
  }

  /**
   * Run container
   */
  async runContainer(
    artifact: ArtifactConfig,
    imageName: string,
    deploymentId: string,
    baseDomain: string
  ): Promise<Deployment> {
    const containerName = generateContainerName(artifact);
    const internalPort = generateInternalPort(artifact);
    const containerPort = artifact.container.port || 8080;

    // Stop and remove existing container
    if (this.containerExists(containerName)) {
      logger.info(`Stopping existing container ${containerName}...`);
      this.stopContainer(containerName);
      this.removeContainer(containerName);
    }

    // Build environment variables
    const envArgs = Object.entries(artifact.container.env || {})
      .map(([key, value]) => `-e ${key}="${value}"`)
      .join(' ');

    // Build extra args
    const extraArgs = artifact.container.extraArgs?.join(' ') || '';
    const memoryArg = artifact.container.memory ? `--memory="${artifact.container.memory}"` : '';
    const cpuArg = artifact.container.cpu ? `--cpus=${artifact.container.cpu}` : '';
    const restartArg = `--restart=${artifact.container.restart || 'unless-stopped'}`;

    // Traefik labels (for local Traefik integration)
    const fullDomain = `${artifact.domain.subdomain}.${baseDomain}`;
    const labels = this.buildTraefikLabels(artifact, fullDomain);
    const labelArgs = labels.map(l => `-l "${l}"`).join(' ');

    // Network (connect to traefik-network if it exists)
    let networkArg = '';
    try {
      execSync('podman network exists traefik-network', { stdio: 'pipe' });
      networkArg = '--network traefik-network';
    } catch {
      // Network doesn't exist, use default
    }

    logger.info(`Starting container ${containerName}...`);

    const runCmd = `podman run -d \\
      --name "${containerName}" \\
      -p 127.0.0.1:${internalPort}:${containerPort} \\
      ${envArgs} \\
      ${labelArgs} \\
      ${memoryArg} \\
      ${cpuArg} \\
      ${restartArg} \\
      ${networkArg} \\
      ${extraArgs} \\
      "${imageName}"`;

    try {
      const output = execSync(runCmd, { encoding: 'utf-8', stdio: 'pipe' });
      const containerId = output.trim();

      const deployment: Deployment = {
        id: deploymentId,
        artifactName: artifact.name,
        domain: fullDomain,
        status: DeploymentStatus.RUNNING,
        containerId,
        port: internalPort,
        createdAt: new Date(),
        updatedAt: new Date(),
        urls: {
          local: `http://${fullDomain}`,
        },
      };

      this.deployments.set(deploymentId, deployment);
      logger.success(`Container ${containerName} running on port ${internalPort}`);
      
      return deployment;
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      throw new Error(`Failed to run container: ${message}`);
    }
  }

  /**
   * Build Traefik labels for container
   */
  private buildTraefikLabels(artifact: ArtifactConfig, domain: string): string[] {
    const routerName = artifact.name.toLowerCase().replace(/[^a-z0-9]/g, '-');
    const containerPort = artifact.container.port || 8080;

    const labels = [
      'traefik.enable=true',
      `traefik.http.routers.${routerName}.rule=Host(\`${domain}\`)`,
      `traefik.http.routers.${routerName}.service=${routerName}`,
      `traefik.http.services.${routerName}.loadbalancer.server.port=${containerPort}`,
    ];

    // Add HTTPS redirect if public
    if (artifact.domain.public) {
      labels.push(
        `traefik.http.routers.${routerName}.entrypoints=websecure`,
        `traefik.http.routers.${routerName}.tls=true`,
        `traefik.http.routers.${routerName}.tls.certresolver=letsencrypt`,
        // HTTP to HTTPS redirect
        `traefik.http.routers.${routerName}-http.rule=Host(\`${domain}\`)`,
        `traefik.http.routers.${routerName}-http.entrypoints=web`,
        `traefik.http.middlewares.${routerName}-redirect.redirectscheme.scheme=https`,
        `traefik.http.routers.${routerName}-http.middlewares=${routerName}-redirect`
      );
    } else {
      labels.push(
        `traefik.http.routers.${routerName}.entrypoints=web`
      );
    }

    return labels;
  }

  /**
   * Stop container
   */
  stopContainer(name: string): boolean {
    try {
      execSync(`podman stop "${name}" 2>/dev/null || true`, { stdio: 'pipe' });
      return true;
    } catch {
      return false;
    }
  }

  /**
   * Remove container
   */
  removeContainer(name: string): boolean {
    try {
      execSync(`podman rm "${name}" 2>/dev/null || true`, { stdio: 'pipe' });
      
      // Remove from deployments
      for (const [id, deployment] of this.deployments.entries()) {
        if (deployment.artifactName.toLowerCase().replace(/[^a-z0-9]/g, '-') === name.replace('ua-', '')) {
          this.deployments.delete(id);
          break;
        }
      }
      
      return true;
    } catch {
      return false;
    }
  }

  /**
   * Get container logs
   */
  getLogs(name: string, tail: number = 50): string {
    try {
      return execSync(`podman logs --tail=${tail} "${name}" 2>&1`, { 
        encoding: 'utf-8', 
        stdio: 'pipe' 
      });
    } catch {
      return 'No logs available';
    }
  }

  /**
   * List all running containers managed by UActions
   */
  listContainers(): ContainerInfo[] {
    try {
      const output = execSync(
        `podman ps -a --filter "label=traefik.enable=true" --format "{{.ID}}|{{.Names}}|{{.Status}}|{{.Ports}}|{{.Image}}"`,
        { encoding: 'utf-8', stdio: 'pipe' }
      );
      
      return output
        .split('\n')
        .filter(line => line.trim())
        .map(line => {
          const [id, name, status, ports, image] = line.split('|');
          return { id, name, status, ports, image };
        });
    } catch {
      return [];
    }
  }

  /**
   * Prune unused images and containers
   */
  prune(): void {
    try {
      logger.info('Pruning unused Podman resources...');
      execSync('podman system prune -f', { stdio: 'pipe' });
      logger.success('Pruned unused resources');
    } catch (error) {
      logger.warn(`Prune failed: ${error}`);
    }
  }

  /**
   * Get deployment by ID
   */
  getDeployment(id: string): Deployment | undefined {
    return this.deployments.get(id);
  }

  /**
   * List all deployments
   */
  listDeployments(): Deployment[] {
    return Array.from(this.deployments.values());
  }

  /**
   * Cleanup temp directory
   */
  cleanup(): void {
    if (existsSync(this.tempDir)) {
      rmSync(this.tempDir, { recursive: true, force: true });
    }
  }
}
