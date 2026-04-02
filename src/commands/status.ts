/**
 * Status Command
 * Show system status
 */
import { Command } from 'commander';
import { DeploymentOrchestrator } from '../services/orchestrator';
import { getLogger } from '../utils/logger';
import chalk from 'chalk';

const logger = getLogger();

export function createStatusCommand(program: Command): void {
  program
    .command('status')
    .description('Show UActions system status')
    .action(() => {
      const orchestrator = new DeploymentOrchestrator();
      const status = orchestrator.getStatus();

      logger.banner('UActions System Status');

      console.log(chalk.bold('Configuration:'));
      console.log(`  Initialized:    ${status.initialized ? chalk.green('Yes') : chalk.red('No')}`);
      console.log(`  Base Domain:    ${status.baseDomain || chalk.gray('Not set')}`);
      console.log();

      console.log(chalk.bold('Services:'));
      console.log(`  Podman:         ${status.podmanInstalled ? chalk.green('Installed') : chalk.red('Not installed')}`);
      console.log(`  Traefik:        ${status.traefikRunning ? chalk.green('Running') : chalk.yellow('Stopped')}`);
      console.log(`  Watcher:        ${status.watcherRunning ? chalk.green('Running') : chalk.yellow('Stopped')}`);
      console.log();

      console.log(chalk.bold('Deployments:'));
      console.log(`  Active:         ${status.deployments}`);

      if (!status.initialized) {
        console.log();
        console.log(chalk.yellow('Run "uactions init" to get started'));
      }
    });
}
