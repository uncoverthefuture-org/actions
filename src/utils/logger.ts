/**
 * Colored console logger
 */
import chalk from 'chalk';
import type { ILogger } from '../types';

export class Logger implements ILogger {
  private verboseMode: boolean;

  constructor(verbose = false) {
    this.verboseMode = verbose;
  }

  setVerbose(verbose: boolean): void {
    this.verboseMode = verbose;
  }

  info(message: string, ...args: unknown[]): void {
    console.log(chalk.blue('ℹ '), message, ...args);
  }

  warn(message: string, ...args: unknown[]): void {
    console.log(chalk.yellow('⚠ '), message, ...args);
  }

  error(message: string, ...args: unknown[]): void {
    console.error(chalk.red('✖ '), message, ...args);
  }

  debug(message: string, ...args: unknown[]): void {
    if (this.verboseMode) {
      console.log(chalk.gray('🐛 '), message, ...args);
    }
  }

  success(message: string, ...args: unknown[]): void {
    console.log(chalk.green('✓ '), message, ...args);
  }

  banner(message: string): void {
    console.log('');
    console.log(chalk.cyan('═'.repeat(60)));
    console.log(chalk.cyan.bold('  ', message));
    console.log(chalk.cyan('═'.repeat(60)));
    console.log('');
  }

  section(title: string): void {
    console.log('');
    console.log(chalk.gray('─'.repeat(50)));
    console.log(chalk.white.bold(title));
    console.log(chalk.gray('─'.repeat(50)));
  }
}

// Singleton instance
let defaultLogger: Logger | null = null;

export function getLogger(verbose = false): Logger {
  if (!defaultLogger) {
    defaultLogger = new Logger(verbose);
  }
  return defaultLogger;
}

export function setVerbose(verbose: boolean): void {
  if (defaultLogger) {
    defaultLogger.setVerbose(verbose);
  }
}
