import React from "react";
import { AbsoluteFill } from "remotion";

export type IconProps = {
  readonly bodyTop: string;
  readonly bodyBottom: string;
  readonly glowTop: string;
  readonly glowBottom: string;
  /** Small sizes (16, 32 px) drop the text lines and the light cone. */
  readonly small: boolean;
};

// macOS icon grid on a 1024 canvas: 824 pt body, 100 pt margin for the shadow.
export const SIZE = 1024;
export const BODY = 824;
export const INSET = (SIZE - BODY) / 2;

/** A superellipse (n = 4) approximates Apple's continuous-corner icon shape. */
export const squircle = (x: number, y: number, w: number, h: number, n = 4) => {
  const pts: string[] = [];
  for (let i = 0; i < 360; i++) {
    const t = (i / 360) * 2 * Math.PI;
    const c = Math.cos(t);
    const s = Math.sin(t);
    const px = x + w / 2 + (w / 2) * Math.sign(c) * Math.abs(c) ** (2 / n);
    const py = y + h / 2 + (h / 2) * Math.sign(s) * Math.abs(s) ** (2 / n);
    pts.push(`${px.toFixed(2)},${py.toFixed(2)}`);
  }
  return `M${pts.join("L")}Z`;
};

type Screen = { x: number; y: number; w: number; h: number };

/** A screen panel: dark bezel with a faint edge, and the screen inset. */
const Panel: React.FC<{ s: Screen; fill: string; children?: React.ReactNode }> = ({ s, fill, children }) => (
  <g>
    <rect x={s.x} y={s.y} width={s.w} height={s.h} rx={28} fill="#0B0D12" stroke="#ffffff" strokeOpacity="0.14" strokeWidth="3" />
    <rect x={s.x + 14} y={s.y + 14} width={s.w - 28} height={s.h - 28} rx={16} fill={fill} />
    {children}
  </g>
);

export const Icon: React.FC<IconProps> = ({ bodyTop, bodyBottom, glowTop, glowBottom, small }) => {
  const body = squircle(INSET, INSET, BODY, BODY);
  const h = small ? 330 : 250;
  const w = small ? 330 : 300;
  const gap = small ? 30 : 32;
  const y = small ? 347 : 318;
  const left: Screen = { x: 512 - gap / 2 - w, y, w, h };
  const right: Screen = { x: 512 + gap / 2, y, w, h };
  // Text cursor (I-beam) on the focused screen.
  const cx = right.x + (small ? 96 : 74);
  const cy = right.y + h / 2;
  const ch = small ? 128 : 96;
  const cw = small ? 22 : 16;

  return (
    <AbsoluteFill>
      <svg width={SIZE} height={SIZE} viewBox={`0 0 ${SIZE} ${SIZE}`}>
        <defs>
          <linearGradient id="body" x1="0" y1="0" x2="0" y2="1">
            <stop offset="0" stopColor={bodyTop} />
            <stop offset="1" stopColor={bodyBottom} />
          </linearGradient>
          <radialGradient id="sheen" cx="0.5" cy="0" r="0.8">
            <stop offset="0" stopColor="#ffffff" stopOpacity="0.16" />
            <stop offset="1" stopColor="#ffffff" stopOpacity="0" />
          </radialGradient>
          <linearGradient id="lit" x1="0" y1="0" x2="1" y2="1">
            <stop offset="0" stopColor={glowTop} />
            <stop offset="1" stopColor={glowBottom} />
          </linearGradient>
          <linearGradient id="dim" x1="0" y1="0" x2="0" y2="1">
            <stop offset="0" stopColor={small ? "#56607A" : "#323A4D"} />
            <stop offset="1" stopColor={small ? "#3D4558" : "#222836"} />
          </linearGradient>
          <linearGradient id="cone" x1="0" y1="1" x2="0" y2="0">
            <stop offset="0" stopColor={glowTop} stopOpacity="0.5" />
            <stop offset="1" stopColor={glowTop} stopOpacity="0.08" />
          </linearGradient>
          <radialGradient id="halo" cx="0.5" cy="0.5" r="0.5">
            <stop offset="0" stopColor={glowBottom} stopOpacity="0.55" />
            <stop offset="1" stopColor={glowBottom} stopOpacity="0" />
          </radialGradient>
          <filter id="shadow" x="-20%" y="-20%" width="140%" height="140%">
            <feDropShadow dx="0" dy="12" stdDeviation="14" floodColor="#000000" floodOpacity="0.35" />
          </filter>
          <clipPath id="bodyClip">
            <path d={body} />
          </clipPath>
        </defs>

        <g filter="url(#shadow)">
          <path d={body} fill="url(#body)" />
        </g>

        <g clipPath="url(#bodyClip)">
          {/* Light on the desk around the focused screen. */}
          <ellipse cx={right.x + w / 2} cy={right.y + h / 2} rx={w * 0.95} ry={h * 1.05} fill="url(#halo)" />
          {/* The line of sight: a cone from the viewer to the focused screen. */}
          {!small && (
            <path
              d={`M512,770 L${right.x + 6},${right.y + h - 6} L${right.x + w - 6},${right.y + h - 6} Z`}
              fill="url(#cone)"
            />
          )}
        </g>

        <Panel s={left} fill="url(#dim)">
          {!small && (
            <g fill="#ffffff" fillOpacity="0.1">
              <rect x={left.x + 46} y={left.y + 70} width={160} height={16} rx={8} />
              <rect x={left.x + 46} y={left.y + 104} width={208} height={16} rx={8} />
              <rect x={left.x + 46} y={left.y + 138} width={126} height={16} rx={8} />
            </g>
          )}
        </Panel>

        <Panel s={right} fill="url(#lit)">
          <g fill="#ffffff">
            <rect x={cx - cw / 2} y={cy - ch / 2} width={cw} height={ch} rx={cw / 2} />
            <rect x={cx - cw * 1.9} y={cy - ch / 2} width={cw * 3.8} height={cw} rx={cw / 2} />
            <rect x={cx - cw * 1.9} y={cy + ch / 2 - cw} width={cw * 3.8} height={cw} rx={cw / 2} />
          </g>
          {!small && (
            <g fill="#ffffff" fillOpacity="0.55">
              <rect x={cx + 42} y={cy - 40} width={128} height={16} rx={8} />
              <rect x={cx + 42} y={cy - 6} width={92} height={16} rx={8} />
              <rect x={cx + 42} y={cy + 28} width={112} height={16} rx={8} />
            </g>
          )}
        </Panel>

        {/* The viewer: a small point of light where the cone starts. */}
        {!small && <circle cx={512} cy={770} r={22} fill={glowTop} stroke="#12151C" strokeWidth="8" />}

        <path d={body} fill="url(#sheen)" />
        <path d={body} fill="none" stroke="#ffffff" strokeOpacity="0.12" strokeWidth="3" />
      </svg>
    </AbsoluteFill>
  );
};
