import type { ReactNode } from 'react';
import { Icon } from './Icon';

export function Keycap({ children }: { children: ReactNode }) {
  return <span className="keycap">{children}</span>;
}

export function OptionLabel({ children }: { children: ReactNode }) {
  return <span className="option-label">{children}</span>;
}

interface SegmentedControlProps<T extends string> {
  value: T;
  options: Array<{ value: T; label: string }>;
  onChange(value: T): void;
  accent?: boolean;
  ariaLabel: string;
}

export function SegmentedControl<T extends string>({
  value,
  options,
  onChange,
  accent = false,
  ariaLabel,
}: SegmentedControlProps<T>) {
  return (
    <div aria-label={ariaLabel} className={`segmented ${accent ? 'segmented-accent' : ''}`} role="group">
      {options.map((option) => (
        <button
          aria-pressed={option.value === value}
          className={option.value === value ? 'is-selected' : undefined}
          key={option.value}
          onClick={() => onChange(option.value)}
          type="button"
        >
          {option.label}
        </button>
      ))}
    </div>
  );
}

interface CheckControlProps {
  checked: boolean;
  label: string;
  onChange(checked: boolean): void;
}

export function CheckControl({ checked, label, onChange }: CheckControlProps) {
  return (
    <label className="check-control">
      <input checked={checked} onChange={(event) => onChange(event.target.checked)} type="checkbox" />
      <span className="check-box">{checked ? <Icon name="check" size={12} strokeWidth={2.6} /> : null}</span>
      <span>{label}</span>
    </label>
  );
}

