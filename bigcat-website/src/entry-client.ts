import '@fontsource/inter/latin-400.css';
import '@fontsource/inter/latin-600.css';
import '@fontsource/space-grotesk/latin-700.css';
import './styles/global.css';
import { initAnalytics } from './client/tracking';
import { initMenu } from './client/menu';
import { initMaps } from './client/map';
import { hydrateIslands } from './client/islands';

initMenu();
initMaps();
initAnalytics();
hydrateIslands();
