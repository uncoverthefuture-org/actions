#!/usr/bin/env node
/**
 * UActions CLI
 * Local container deployment system
 * Inspired by GitHub Actions SSH Container Deploy
 */
import { Command } from 'commander';
import chalk from 'chalk';
import { createInitCommand, createDeployCommand, createWatchCommand, createListCommand, createStatusCommand, createCreateCommand } from './commands';
import { getLogger } from './utils/logger';

const logger = getLogger();

const program = new Command();

// CLI metadata
program
  .name('uactions')
  .description('Local container deployment with Podman and Traefik')
  .version('1.0.0', '-v, --version', 'Display version number')
  .option('--verbose', 'Enable verbose logging', false)
  .helpOption('-h, --help', 'Display help for command');

// Global options handler
program.hook('preAction', (thisCommand) => {
  const options = thisCommand.opts();
  if (options.verbose) {
    getLogger().setVerbose(true);
  }
});

// Register commands
createInitCommand(program);
createDeployCommand(program);
createWatchCommand(program);
createListCommand(program);
createStatusCommand(program);
createCreateCommand(program);

// Global error handler
process.on('unhandledRejection', (error) => {
  logger.error(`Unhandled error: ${error}`);
  process.exit(1);
});

process.on('uncaughtException', (error) => {
  logger.error(`Uncaught exception: ${error}`);
  process.exit(1);
});

// Banner on direct execution
if (require.main === module) {
  console.log(chalk.cyan(`
╔═══════════════════════════════════════════════════════════╗
║                                                           ║
║   ██╗   ██╗ █████╗  ██████╗████████╗██╗ ██████╗ ███╗   ██╗║
║   ██║   ██║██╔══██╗██╔════╝╚══██╔══╝██║██╔═══██╗████╗  ██║║
║   ██║   ██║███████║██║        ██║   ██║██║   ██║██╔██╗ ██║║
║   ██║   ██║██╔══██║██║        ██║   ██║██║   ██║██║╚██╗██║║
║   ╚██████╔╝██║  ██║╚██████╗   ██║   ██║╚██████╔╝██║ ╚████║║
║    ╚═════╝ ╚═╝  ╚═╝ ╚═════╝   ╚═╝   ╚═╝ ╚═════╝ ╚═╝  ╚═══╝║
║                                                           ║
║     Local Container Deployment with Podman & Traefik     ║
║                                                           ║
╚═══════════════════════════════════════════════════════════╝
`));
}

// Parse arguments
program.parse();
