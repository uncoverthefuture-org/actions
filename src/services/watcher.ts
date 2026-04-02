/**
 * File Watcher Service
 * Watches the uactions folder for new artifact.json files
 * Automatically triggers deployments when artifacts are created/modified
 */
import * as chokidar from 'chokidar';
import { existsSync, mkdirSync } from 'fs';
import { join, basename, dirname } from 'path';
import { homedir } from 'os';
import type { ArtifactConfig } from '../types';
import { WatcherEventType } from '../types';
import { loadArtifact, hasArtifact } from '../utils/artifact';
import { getLogger } from '../utils/logger';

const logger = getLogger();

export type WatcherCallback = (event: { type: WatcherEventType; path: string; artifact?: ArtifactConfig }) => Promise<void> | void;

export class UActionsWatcher {
  private uactionsPath: string;
  private watcher?: chokidar.FSWatcher;
  private callbacks: WatcherCallback[] = [];
  private isWatching = false;

  constructor(uactionsPath?: string) {
    this.uactionsPath = uactionsPath || join(homedir(), 'uactions');
    this.ensureDirectory();
  }

  /**
   * Ensure uactions directory exists
   */
  private ensureDirectory(): void {
    if (!existsSync(this.uactionsPath)) {
      logger.info(`Creating uactions directory at ${this.uactionsPath}`);
      mkdirSync(this.uactionsPath, { recursive: true });
    }
  }

  /**
   * Get the uactions path
   */
  getPath(): string {
    return this.uactionsPath;
  }

  /**
   * Register a callback for watcher events
   */
  onEvent(callback: WatcherCallback): void {
    this.callbacks.push(callback);
  }

  /**
   * Remove a callback
   */
  offEvent(callback: WatcherCallback): void {
    this.callbacks = this.callbacks.filter(cb => cb !== callback);
  }

  /**
   * Emit event to all callbacks
   */
  private async emitEvent(event: { type: WatcherEventType; path: string; artifact?: ArtifactConfig }): Promise<void> {
    for (const callback of this.callbacks) {
      try {
        await callback(event);
      } catch (error) {
        logger.error(`Watcher callback error: ${error}`);
      }
    }
  }

  /**
   * Start watching the uactions folder
   */
  async start(): Promise<void> {
    if (this.isWatching) {
      logger.warn('Watcher is already running');
      return;
    }

    logger.info(`Starting watcher on ${this.uactionsPath}`);

    this.watcher = chokidar.watch(
      join(this.uactionsPath, '**/artifact.json'),
      {
        ignored: /node_modules/,
        persistent: true,
        ignoreInitial: false, // Process existing files on start
        depth: 2, // Only watch 2 levels deep (uactions/<project>/artifact.json)
        awaitWriteFinish: {
          stabilityThreshold: 500,
          pollInterval: 100,
        },
      }
    );

    // Add event
    this.watcher.on('add', async (filePath: string) => {
      logger.debug(`File added: ${filePath}`);
      await this.handleFileEvent(filePath, WatcherEventType.CREATED);
    });

    // Change event
    this.watcher.on('change', async (filePath: string) => {
      logger.debug(`File changed: ${filePath}`);
      await this.handleFileEvent(filePath, WatcherEventType.MODIFIED);
    });

    // Unlink event
    this.watcher.on('unlink', async (filePath: string) => {
      logger.debug(`File removed: ${filePath}`);
      await this.handleFileEvent(filePath, WatcherEventType.DELETED);
    });

    // Error event
    this.watcher.on('error', (error: Error) => {
      logger.error(`Watcher error: ${error}`);
    });

    // Ready event
    this.watcher.on('ready', () => {
      logger.success('Watcher is ready');
      this.isWatching = true;
    });

    // Wait for ready
    await new Promise<void>((resolve) => {
      if (this.isWatching) {
        resolve();
        return;
      }
      
      const checkReady = setInterval(() => {
        if (this.isWatching) {
          clearInterval(checkReady);
          resolve();
        }
      }, 100);
    });
  }

  /**
   * Handle file events
   */
  private async handleFileEvent(filePath: string, type: WatcherEventType): Promise<void> {
    const folderPath = dirname(filePath);
    const projectName = basename(folderPath);

    const event = {
      type,
      path: folderPath,
    };

    // Load artifact if file exists
    if (type !== WatcherEventType.DELETED) {
      const result = loadArtifact(filePath);
      if (result.success && result.data) {
        Object.assign(event, { artifact: result.data });
        logger.info(`${type === WatcherEventType.CREATED ? 'New' : 'Updated'} artifact detected: ${result.data.name}`);
      } else {
        logger.warn(`Invalid artifact.json in ${folderPath}: ${result.error}`);
        return;
      }
    } else {
      logger.info(`Artifact removed: ${projectName}`);
    }

    await this.emitEvent(event);
  }

  /**
   * Scan for existing artifacts
   */
  async scanExisting(): Promise<ArtifactConfig[]> {
    const artifacts: ArtifactConfig[] = [];
    
    if (!existsSync(this.uactionsPath)) {
      return artifacts;
    }

    const { readdirSync, statSync } = await import('fs');
    const entries = readdirSync(this.uactionsPath);

    for (const entry of entries) {
      const entryPath = join(this.uactionsPath, entry);
      
      try {
        const stat = statSync(entryPath);
        if (stat.isDirectory() && hasArtifact(entryPath)) {
          const artifactPath = join(entryPath, 'artifact.json');
          const result = loadArtifact(artifactPath);
          
          if (result.success && result.data) {
            artifacts.push(result.data);
            logger.debug(`Found existing artifact: ${result.data.name}`);
          }
        }
      } catch {
        // Ignore errors
      }
    }

    return artifacts;
  }

  /**
   * Create a new artifact folder
   */
  async createArtifactFolder(name: string): Promise<string> {
    const folderPath = join(this.uactionsPath, name);
    
    if (!existsSync(folderPath)) {
      mkdirSync(folderPath, { recursive: true });
    }

    return folderPath;
  }

  /**
   * Stop watching
   */
  async stop(): Promise<void> {
    if (this.watcher) {
      await this.watcher.close();
      this.watcher = undefined;
      this.isWatching = false;
      logger.info('Watcher stopped');
    }
  }

  /**
   * Check if watcher is running
   */
  isRunning(): boolean {
    return this.isWatching;
  }
}
