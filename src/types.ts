import type { ComponentType } from 'react';

export type ToolCategory =
  | 'encoding'
  | 'formatting'
  | 'style'
  | 'image'
  | 'system'
  | 'network';

export type ToolLayout = 'dual' | 'stacked' | 'form' | 'canvas';

export interface ToolDefinition {
  id: string;
  name: string;
  category: ToolCategory;
  layout: ToolLayout;
  icon: string;
  aliases: string[];
  implemented: boolean;
  component?: ComponentType;
}

export interface CategoryDefinition {
  id: ToolCategory;
  title: string;
  icon: string;
  tint: string;
}

export type ConvertDirection = 'encode' | 'decode';

export interface ConversionResult {
  text: string;
  error?: string;
}

