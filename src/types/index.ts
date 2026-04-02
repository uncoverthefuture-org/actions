// Export all types
export * from './artifact';

// Additional shared types

/** CLI Options */
export interface CLIOptions {
  verbose?: boolean;
  dryRun?: boolean;
  config?: string;
}

/** Service result wrapper */
export interface ServiceResult<T = void> {
  success: boolean;
  data?: T;
  error?: string;
}

/** Logger interface */
export interface ILogger {
  info(message: string, ...args: unknown[]): void;
  warn(message: string, ...args: unknown[]): void;
  error(message: string, ...args: unknown[]): void;
  debug(message: string, ...args: unknown[]): void;
  success(message: string, ...args: unknown[]): void;
}

/** Platform detection */
export enum Platform {
  MACOS = 'darwin',
  LINUX = 'linux',
  WINDOWS = 'win32',
}

/** Command result */
export interface CommandResult {
  stdout: string;
  stderr: string;
  exitCode: number;
}
