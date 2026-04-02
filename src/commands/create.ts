/**
 * Create Command
 * Create a new artifact
 */
import { Command } from 'commander';
import { writeFileSync, existsSync } from 'fs';
import { join } from 'path';
import { UActionsWatcher } from '../services/watcher';
import { getLogger } from '../utils/logger';
import type { ArtifactConfig } from '../types';

const logger = getLogger();

export function createCreateCommand(program: Command): void {
  program
    .command('create <name>')
    .description('Create a new artifact in the uactions folder')
    .option('-s, --source <url>', 'Source URL (git repo, tarball)', 'https://github.com/example/repo.git')
    .option('-d, --domain <subdomain>', 'Subdomain for deployment')
    .option('-p, --port <port>', 'Container port', '8080')
    .option('-t, --type <type>', 'Project type (php-laravel, node, python, static)', 'static')
    .action(async (name, options) => {
      const watcher = new UActionsWatcher();

      // Generate subdomain from name if not provided
      const subdomain = options.domain || name.toLowerCase().replace(/[^a-z0-9]/g, '-');

      const artifact: ArtifactConfig = {
        version: '1.0.0',
        name,
        source: {
          url: options.source,
        },
        domain: {
          subdomain,
          public: false,
        },
        container: {
          port: parseInt(options.port, 10),
          dockerfile: './Dockerfile',
        },
        build: {
          autoBuild: true,
        },
      };

      try {
        const folderPath = await watcher.createArtifactFolder(name);
        const artifactPath = join(folderPath, 'artifact.json');

        if (existsSync(artifactPath)) {
          logger.error(`Artifact already exists: ${artifactPath}`);
          logger.info('Use "uactions deploy" to deploy it');
          process.exit(1);
        }

        writeFileSync(artifactPath, JSON.stringify(artifact, null, 2));
        
        logger.success(`Created artifact: ${artifactPath}`);
        logger.info(`Name: ${name}`);
        logger.info(`Subdomain: ${subdomain}`);
        logger.info(`Source: ${options.source}`);
        logger.info('');
        logger.info('Next steps:');
        logger.info(`1. Edit ${artifactPath} if needed`);
        logger.info(`2. Create a Dockerfile for your ${options.type} project`);
        logger.info(`3. Run: uactions deploy ${name}`);
      } catch (error) {
        logger.error(`Failed to create artifact: ${error}`);
        process.exit(1);
      }
    });
}
