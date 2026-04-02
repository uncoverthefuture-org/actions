/**
 * List Command
 * List deployments and artifacts
 */
import { Command } from 'commander';
import { DeploymentOrchestrator } from '../services/orchestrator';
import { UActionsWatcher } from '../services/watcher';
import { getLogger } from '../utils/logger';
import chalk from 'chalk';

const logger = getLogger();

export function createListCommand(program: Command): void {
  program
    .command('list')
    .description('List deployments and artifacts')
    .option('-a, --artifacts', 'List artifacts in uactions folder', false)
    .action(async (options) => {
      const orchestrator = new DeploymentOrchestrator();
      const status = orchestrator.getStatus();

      if (options.artifacts) {
        logger.banner('Artifacts in UActions Folder');
        const watcher = new UActionsWatcher();
        const artifacts = await watcher.scanExisting();
        
        if (artifacts.length === 0) {
          logger.info('No artifacts found. Create one with: uactions create <name>');
          return;
        }

        console.log(chalk.cyan('Name'.padEnd(20)), chalk.cyan('Domain'), chalk.cyan('Source URL'));
        console.log(chalk.gray('-'.repeat(80)));
        
        for (const artifact of artifacts) {
          console.log(
            artifact.name.padEnd(20),
            `${artifact.domain.subdomain}.${status.baseDomain}`.padEnd(30),
            artifact.source.url.slice(0, 40)
          );
        }
      } else {
        logger.banner('Active Deployments');
        const deployments = orchestrator.listDeployments();
        
        if (deployments.length === 0) {
          logger.info('No active deployments');
          return;
        }

        console.log(
          chalk.cyan('Name'.padEnd(20)),
          chalk.cyan('Status'.padEnd(12)),
          chalk.cyan('Domain'),
          chalk.cyan('Port')
        );
        console.log(chalk.gray('-'.repeat(80)));
        
        for (const deployment of deployments) {
          const statusColor = deployment.status === 'running' ? chalk.green : 
                           deployment.status === 'error' ? chalk.red : chalk.yellow;
          console.log(
            deployment.artifactName.padEnd(20),
            statusColor(deployment.status.padEnd(12)),
            deployment.domain.padEnd(30),
            deployment.port?.toString() || '-'
          );
        }
      }
    });
}
