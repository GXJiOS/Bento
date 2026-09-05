import {
  ArrowDownUp,
  ArrowLeftRight,
  Braces,
  Check,
  CheckCircle2,
  ChevronRight,
  Circle,
  ClipboardPaste,
  CodeXml,
  Command,
  Copy,
  Cpu,
  Download,
  FileUp,
  Globe2,
  Image,
  Link2,
  MoreHorizontal,
  Palette,
  Search,
  Settings,
  Star,
  TextCursorInput,
  Trash2,
  Wrench,
  X,
  XCircle,
  type LucideIcon,
} from 'lucide-react';

const icons: Record<string, LucideIcon> = {
  'arrow-down-up': ArrowDownUp,
  'arrow-left-right': ArrowLeftRight,
  braces: Braces,
  check: Check,
  'check-circle': CheckCircle2,
  chevron: ChevronRight,
  circle: Circle,
  'clipboard-paste': ClipboardPaste,
  'code-xml': CodeXml,
  command: Command,
  copy: Copy,
  cpu: Cpu,
  download: Download,
  'file-up': FileUp,
  'globe-2': Globe2,
  image: Image,
  link: Link2,
  more: MoreHorizontal,
  palette: Palette,
  search: Search,
  settings: Settings,
  star: Star,
  'text-cursor-input': TextCursorInput,
  trash: Trash2,
  wrench: Wrench,
  x: X,
  'x-circle': XCircle,
};

interface IconProps {
  name: string;
  size?: number;
  strokeWidth?: number;
  className?: string;
}

export function Icon({ name, size = 16, strokeWidth = 1.8, className }: IconProps) {
  const Component = icons[name] ?? Wrench;
  return <Component aria-hidden="true" className={className} size={size} strokeWidth={strokeWidth} />;
}

