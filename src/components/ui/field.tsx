import { useId, type ChangeEvent, type ReactNode } from "react";

export function SoftField({
  label,
  name,
  type = "text",
  placeholder,
  required,
  minLength,
  maxLength,
  autoComplete,
  trailing,
  defaultValue,
  value,
  onChange,
}: {
  label: string;
  name: string;
  type?: string;
  placeholder?: string;
  required?: boolean;
  minLength?: number;
  maxLength?: number;
  autoComplete?: string;
  trailing?: ReactNode;
  defaultValue?: string;
  value?: string;
  onChange?: (e: ChangeEvent<HTMLInputElement>) => void;
}) {
  // Inputs and their trailing controls (e.g. show/hide password) live as
  // siblings under a div, NOT nested inside a single <label>. On iOS Safari,
  // a button inside a label has its tap swallowed and routed to the input
  // instead. The label is associated to the input via htmlFor.
  const id = useId();
  return (
    <div className="mb-3.5 block">
      <label
        htmlFor={id}
        className="mb-1.5 block text-[12.5px] font-semibold text-ink-soft"
      >
        {label}
      </label>
      <div className="flex items-center gap-2 rounded-2xl border-[1.5px] border-line bg-surface px-4 py-3.5 focus-within:border-ink">
        <input
          id={id}
          name={name}
          type={type}
          placeholder={placeholder}
          required={required}
          minLength={minLength}
          maxLength={maxLength}
          autoComplete={autoComplete}
          defaultValue={defaultValue}
          value={value}
          onChange={onChange}
          className="flex-1 border-none bg-transparent text-[15px] text-ink outline-none placeholder:text-ink-soft/60"
        />
        {trailing}
      </div>
    </div>
  );
}
