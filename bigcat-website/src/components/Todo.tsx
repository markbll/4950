import { showTodoMarkers } from '../config';

/** Visible TODO marker for missing business facts / content. Hidden in production builds. */
export function Todo({ label }: { label: string }) {
  if (!showTodoMarkers) return null;
  return <span className="todo">[TODO: {label}]</span>;
}
