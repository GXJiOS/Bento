import { Base64Tool } from '../tools/Base64Tool';
import { UnicodeTool } from '../tools/UnicodeTool';
import { UrlTool } from '../tools/UrlTool';
import type { CategoryDefinition, ToolCategory, ToolDefinition, ToolLayout } from '../types';

export const categories: CategoryDefinition[] = [
  { id: 'encoding', title: '编解码', icon: 'code-xml', tint: '#0a84ff' },
  { id: 'formatting', title: '格式化 / 代码', icon: 'braces', tint: '#bf5af2' },
  { id: 'style', title: '样式与设计', icon: 'palette', tint: '#ff375f' },
  { id: 'image', title: '图像与资源', icon: 'image', tint: '#30d158' },
  { id: 'system', title: '系统集成', icon: 'cpu', tint: '#64d2ff' },
  { id: 'network', title: '网络', icon: 'globe-2', tint: '#ff9f0a' },
];

type PlannedTool = [id: string, name: string, category: ToolCategory, layout: ToolLayout];

const planned: PlannedTool[] = [
  ['htmlentity', 'HTML 实体', 'encoding', 'dual'],
  ['escape', '字符串转义', 'encoding', 'dual'],
  ['jwt', 'JWT 解析', 'encoding', 'form'],
  ['timestamp', '时间戳转换', 'encoding', 'form'],
  ['radix', '进制转换', 'encoding', 'form'],
  ['uuid', 'UUID 生成', 'encoding', 'form'],
  ['hash', '哈希计算', 'encoding', 'form'],
  ['json', 'JSON 工具箱', 'formatting', 'dual'],
  ['json2model', 'JSON → 模型', 'formatting', 'dual'],
  ['jsondiff', 'JSON Diff', 'formatting', 'stacked'],
  ['jsontree', 'JSON 树', 'formatting', 'stacked'],
  ['case', '命名转换', 'formatting', 'dual'],
  ['textdiff', '文本 Diff', 'formatting', 'stacked'],
  ['yaml', 'YAML 互转', 'formatting', 'dual'],
  ['cron', 'Cron 解析', 'formatting', 'form'],
  ['markdown', 'Markdown 预览', 'formatting', 'stacked'],
  ['regex', '正则测试器', 'formatting', 'stacked'],
  ['color', '颜色转换', 'style', 'form'],
  ['contrast', '对比度检查', 'style', 'form'],
  ['palette', '调色板生成', 'style', 'canvas'],
  ['shadow', '阴影生成', 'style', 'canvas'],
  ['gradient', '渐变生成', 'style', 'canvas'],
  ['css2swiftui', 'CSS → SwiftUI', 'style', 'dual'],
  ['picker', '屏幕取色', 'style', 'form'],
  ['typescale', '字号阶梯', 'style', 'canvas'],
  ['unit', '单位换算', 'style', 'form'],
  ['grid', '间距栅格', 'style', 'canvas'],
  ['font', '字体预览', 'style', 'canvas'],
  ['easing', '缓动曲线', 'style', 'canvas'],
  ['imgconvert', '图片压缩 / 转换', 'image', 'canvas'],
  ['iconset', '图标切图套件', 'image', 'canvas'],
  ['exif', 'EXIF 查看', 'image', 'form'],
  ['imgbase64', '图片 ⇄ Base64', 'image', 'dual'],
  ['qrcode', '二维码', 'image', 'canvas'],
  ['svg', 'SVG 工具', 'image', 'stacked'],
  ['lottie', 'Lottie 检查', 'image', 'form'],
  ['clipmonitor', '剪贴板监听', 'system', 'form'],
  ['cliphistory', '剪贴板历史', 'system', 'stacked'],
  ['services', 'Services 菜单', 'system', 'form'],
  ['hotkey', '全局热键', 'system', 'form'],
  ['shortcuts', '快捷指令动作', 'system', 'form'],
  ['cli', 'CLI 伴生', 'system', 'form'],
  ['drophub', '拖放中枢', 'system', 'form'],
  ['pipeline', '工具链', 'system', 'stacked'],
  ['http', 'HTTP 测试器', 'network', 'stacked'],
  ['headers', '响应头分析', 'network', 'stacked'],
  ['websocket', 'WebSocket', 'network', 'stacked'],
  ['ipinfo', 'IP 信息', 'network', 'form'],
  ['dns', 'DNS / Ping', 'network', 'stacked'],
  ['cert', '证书检查', 'network', 'form'],
];

const migrated: ToolDefinition[] = [
  {
    id: 'base64',
    name: 'Base64 编解码',
    category: 'encoding',
    layout: 'dual',
    icon: 'arrow-left-right',
    aliases: ['b64', 'base64', 'bianma', 'bjm'],
    implemented: true,
    component: Base64Tool,
  },
  {
    id: 'url',
    name: 'URL 编解码',
    category: 'encoding',
    layout: 'dual',
    icon: 'link',
    aliases: ['url', 'percent', 'urlencode', 'wz', 'ljbm'],
    implemented: true,
    component: UrlTool,
  },
  {
    id: 'unicode',
    name: 'Unicode 转义',
    category: 'encoding',
    layout: 'dual',
    icon: 'text-cursor-input',
    aliases: ['unicode', 'u', 'escape', 'zy', 'unizy'],
    implemented: true,
    component: UnicodeTool,
  },
];

export const tools: ToolDefinition[] = [
  ...migrated,
  ...planned.map(([id, name, category, layout]) => ({
    id,
    name,
    category,
    layout,
    icon: 'wrench',
    aliases: [],
    implemented: false,
  })),
];

export const migratedTools = tools.filter((tool) => tool.implemented);

export function toolById(id: string | null): ToolDefinition | undefined {
  return tools.find((tool) => tool.id === id);
}

export function categoryById(id: ToolCategory): CategoryDefinition {
  return categories.find((category) => category.id === id) ?? categories[0];
}

export function searchTools(query: string): ToolDefinition[] {
  const normalized = query.trim().toLowerCase();
  if (!normalized) return tools;
  return tools
    .map((tool) => {
      const name = tool.name.toLowerCase();
      let rank = Number.POSITIVE_INFINITY;
      if (name.startsWith(normalized)) rank = 0;
      else if (tool.aliases.some((alias) => alias.startsWith(normalized))) rank = 1;
      else if (name.includes(normalized)) rank = 2;
      else if (tool.aliases.some((alias) => alias.includes(normalized))) rank = 3;
      return { tool, rank };
    })
    .filter(({ rank }) => Number.isFinite(rank))
    .sort((a, b) => a.rank - b.rank || Number(b.tool.implemented) - Number(a.tool.implemented))
    .map(({ tool }) => tool);
}

