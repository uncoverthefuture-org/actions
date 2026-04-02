/**
 * Artifact configuration - defines a deployable container
 * This is the core configuration file that users create in their uactions folders
 */

export interface ArtifactConfig {
  /** Schema version */
  version: '1.0.0';
  
  /** Human readable name for this deployment */
  name: string;
  
  /** URL to pull the source code from */
  source: {
    /** Repository URL (git, tarball, etc.) */
    url: string;
    /** Optional ref (branch, tag, commit) */
    ref?: string;
    /** Authentication if needed */
    auth?: {
      type: 'token' | 'basic';
      token?: string;
      username?: string;
      password?: string;
    };
  };
  
  /** Domain configuration */
  domain: {
    /** Local subdomain (e.g., "tea" for tea.sirdavis99.pc) */
    subdomain: string;
    /** Whether this should be publicly accessible (requires public domain) */
    public?: boolean;
    /** Custom domain if public is true */
    customDomain?: string;
  };
  
  /** Container configuration */
  container: {
    /** Container port (default: 8080) */
    port?: number;
    /** Dockerfile path relative to source root (default: ./Dockerfile) */
    dockerfile?: string;
    /** Build context */
    context?: string;
    /** Environment variables */
    env?: Record<string, string>;
    /** Memory limit (default: 512m) */
    memory?: string;
    /** CPU limit (default: 0.5) */
    cpu?: number;
    /** Restart policy (default: unless-stopped) */
    restart?: 'always' | 'unless-stopped' | 'on-failure' | 'no';
    /** Additional run args */
    extraArgs?: string[];
    /** Health check path (default: /) */
    healthCheck?: string;
  };
  
  /** Build configuration */
  build?: {
    /** Whether to auto-build on source change */
    autoBuild?: boolean;
    /** Build args */
    args?: Record<string, string>;
  };
  
  /** GitHub PR configuration */
  github?: {
    /** Auto-create PR when artifact is created */
    autoPR?: boolean;
    /** Target repository */
    repo?: string;
    /** Target branch */
    branch?: string;
    /** PR title template */
    prTitle?: string;
  };
  
  /** Metadata */
  meta?: {
    /** Description */
    description?: string;
    /** Tags */
    tags?: string[];
    /** Icon/emoji */
    icon?: string;
  };
}

/** Deployment status */
export enum DeploymentStatus {
  PENDING = 'pending',
  PULLING = 'pulling',
  BUILDING = 'building',
  DEPLOYING = 'deploying',
  RUNNING = 'running',
  ERROR = 'error',
  STOPPED = 'stopped',
}

/** Deployment record */
export interface Deployment {
  /** Unique deployment ID */
  id: string;
  /** Artifact name */
  artifactName: string;
  /** Full domain */
  domain: string;
  /** Status */
  status: DeploymentStatus;
  /** Container ID */
  containerId?: string;
  /** Port mapping */
  port?: number;
  /** When created */
  createdAt: Date;
  /** Last updated */
  updatedAt: Date;
  /** Error message if any */
  error?: string;
  /** URLs */
  urls: {
    local: string;
    public?: string;
  };
}

/** UActions configuration (stored in ~/.uactions/config.json) */
export interface UActionsConfig {
  /** Installation ID */
  installId: string;
  /** User's base domain (e.g., sirdavis99.pc) */
  baseDomain: string;
  /** Whether public access is enabled */
  publicEnabled: boolean;
  /** Path to uactions folder */
  uactionsPath: string;
  /** Traefik configuration */
  traefik: {
    enabled: boolean;
    version: string;
    acmeEmail?: string;
    dashboardEnabled: boolean;
  };
  /** Podman configuration */
  podman: {
    socketPath?: string;
    useRootless: boolean;
  };
  /** First run completed */
  initialized: boolean;
}

/** Watcher event types */
export enum WatcherEventType {
  CREATED = 'created',
  MODIFIED = 'modified',
  DELETED = 'deleted',
}

/** File watcher event */
export interface WatcherEvent {
  type: WatcherEventType;
  path: string;
  /** Artifact config if valid */
  artifact?: ArtifactConfig;
}
