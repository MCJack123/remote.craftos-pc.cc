export interface ServerConfig {
  ip: string;
  port: number;
  isSecure: boolean;
  certPath?: string;
  keyPath?: string;
  enablePM2?: boolean;
  enableMetrics?: boolean;
  metricsPort?: number;
}

export const defaultConfig: ServerConfig = {
  ip: "localhost",
  port: 4000,
  isSecure: false,
  enablePM2: false,
  enableMetrics: false,
  metricsPort: 9991
};
