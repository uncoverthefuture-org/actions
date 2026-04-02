/**
 * Watch Command
 * Start the file watcher
 */
import { Command } from 'commander';
import { DeploymentOrchestrator } from '../services/orchestrator';
import { getLogger } from '../utils/logger';

const logger = getLogger();

export function createWatchCommand(program: Command): void {
  program
    .command('watch')
    .description('Start watching the uactions folder for new artifacts')
    .option('-d, --detach', 'Run in detached mode (background)')
    .action(async (_options) => {
      const orchestrator = new DeploymentOrchestrator();
      const status = orchestrator.getStatus();

      if (!status.initialized) {
        logger.error('UActions is not initialized. Run: uactions init');
        process.exit(1);
      }

      logger.banner('Starting UActions Watcher');
      logger.info(`Watching: ~/uactions/`);
      logger.info('Press Ctrl+C to stop\n');

      try {
        await orchestrator.startWatcher();

        // Keep running until interrupted
        process.on('SIGINT', async () => {
          logger.info('\nStopping watcher...');
          await orchestrator.stopWatcher();
          process.exit(0);
        });

        process.on('SIGTERM', async () => {
          logger.info('\nStopping watcher...');
          await orchestrator.stopWatcher();
          process.exit(0);
        });

        // Keep the process alive
        setInterval(() => {}, 1000);
      } catch (error) {
        logger.error(`Watcher failed: ${error}`);
        process.exit(1);
      }
    });
}
