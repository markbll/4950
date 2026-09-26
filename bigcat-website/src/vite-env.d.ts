/// <reference types="vite/client" />

declare const __BUILD_YEAR__: number;

interface ImportMetaEnv {
  readonly VITE_SITE_URL?: string;
  readonly VITE_SITE_ENV?: string;
  readonly VITE_GA_MEASUREMENT_ID?: string;
}
