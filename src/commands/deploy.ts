/**
 * Deploy Command
 * Deploy an artifact manually
 */
import { Command } from 'commander';
import { DeploymentOrchestrator } from '../services/orchestrator';
import { loadArtifact } from '../utils/artifact';
import { getLogger } from '../utils/logger';
import { join } from 'path';
import { homedir } from 'os';
import { existsSync } from 'fs';

const logger = getLogger();

export function createDeployCommand(program: Command): void {
  program
    .command('deploy [name]')
    .description('Deploy an artifact')
    .option('-s, --source <url>', 'Source URL to deploy')
    .option('-d, --domain <subdomain>', 'Subdomain for deployment')
    .option('-p, --port <port>', 'Container port', '8080')
    .option('--file <path>', 'Path to artifact.json file')
    .option('--create-pr', 'Create a GitHub PR with Dockerfile')
    .action(async (name, options) => {
      const orchestrator = new DeploymentOrchestrator();
      const status = orchestrator.getStatus();

      if (!status.initialized) {
        logger.error('UActions is not initialized. Run: uactions init');
        process.exit(1);
      }

      try {
        let artifact;

        // Load from file if specified
        if (options.file) {
          const result = loadArtifact(options.file);
          if (!result.success) {
            logger.error(`Failed to load artifact: ${result.error}`);
            process.exit(1);
          }
          artifact = result.data!;
        }
        // Load from uactions folder
        else if (name) {
          const artifactPath = join(homedir(), 'uactions', name, 'artifact.json');
          if (!existsSync(artifactPath)) {
            logger.error(`Artifact not found: ${artifactPath}`);
            logger.info('Run "uactions list" to see available artifacts');
            process.exit(1);
          }
          const result = loadArtifact(artifactPath);
          if (!result.success) {
            logger.error(`Failed to load artifact: ${result.error}`);
            process.exit(1);
          }
          artifact = result.data!;
        }
        // Create from CLI options
        else if (options.source && options.domain) {
          artifact = {
            version: '1.0.0' as const,
            name: name || options.domain,
            source: {
              url: options.source,
            },
            domain: {
              subdomain: options.domain,
            },
            container: {
              port: parseInt(options.port, 10),
            },
          };
        }
        else {
          logger.error('Please provide either:');
          logger.error('  - An artifact name (from ~/uactions/)');
          logger.error('  - A file path (--file)');
          logger.error('  - Source URL and domain (--source and --domain)');
          process.exit(1);
        }

        // Deploy
        const deployment = await orchestrator.deployArtifact(artifact);

        logger.success(`Deployment successful!`);
        logger.info(`URL: ${deployment.urls.local}`);
        
        if (options.createPr) {
          logger.info('Creating GitHub PR...');
          // PR creation is handled in orchestrator if autoPR is set
        }
      } catch (error) {
        logger.error(`Deployment failed: ${error}`);
        process.exit(1);
      }
    });
}
