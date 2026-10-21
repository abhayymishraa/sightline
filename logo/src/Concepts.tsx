import React from "react";
import { AbsoluteFill } from "remotion";
import { loadFont } from "@remotion/google-fonts/Geist";
import { BODY, INSET, Icon, SIZE, squircle } from "./Icon";

const { fontFamily } = loadFont("normal", { weights: ["500", "700"], subsets: ["latin"] });

const BLUE = "#1C9CF0";
const BLUE_LIGHT = "#7CCBFF";
const body = squircle(INSET, INSET, BODY, BODY);

type ConceptProps = { readonly small: boolean };

/** The shared macOS body: squircle, drop shadow, top sheen and hairline edge. */
const Body: React.FC<{ id: string; top: string; bottom: string; children: React.ReactNode }> = ({ id, top, bottom, children }) => (
  <AbsoluteFill>
    <svg width={SIZE} height={SIZE} viewBox={`0 0 ${SIZE} ${SIZE}`}>
      <defs>
        <linearGradient id={`${id}-body`} x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stopColor={top} />
          <stop offset="1" stopColor={bottom} />
        </linearGradient>
        <radialGradient id={`${id}-sheen`} cx="0.5" cy="0" r="0.8">
          <stop offset="0" stopColor="#ffffff" stopOpacity="0.18" />
          <stop offset="1" stopColor="#ffffff" stopOpacity="0" />
        </radialGradient>
        <filter id={`${id}-shadow`} x="-20%" y="-20%" width="140%" height="140%">
          <feDropShadow dx="0" dy="12" stdDeviation="14" floodColor="#000000" floodOpacity="0.32" />
        </filter>
        <clipPath id={`${id}-clip`}>
          <path d={body} />
        </clipPath>
        <linearGradient id={`${id}-blue`} x1="0" y1="0" x2="1" y2="1">
          <stop offset="0" stopColor={BLUE_LIGHT} />
          <stop offset="1" stopColor={BLUE} />
        </linearGradient>
      </defs>
      <g filter={`url(#${id}-shadow)`}>
        <path d={body} fill={`url(#${id}-body)`} />
      </g>
      <g clipPath={`url(#${id}-clip)`}>{children}</g>
      <path d={body} fill={`url(#${id}-sheen)`} />
      <path d={body} fill="none" stroke="#ffffff" strokeOpacity="0.14" strokeWidth="3" />
    </svg>
  </AbsoluteFill>
);

/** An I-beam text cursor centred at (x, y). */
const Caret: React.FC<{ x: number; y: number; h: number; w: number; fill: string; opacity?: number }> = ({ x, y, h, w, fill, opacity = 1 }) => (
  <g fill={fill} opacity={opacity}>
    <rect x={x - w / 2} y={y - h / 2} width={w} height={h} rx={w / 2} />
    <rect x={x - w * 1.9} y={y - h / 2} width={w * 3.8} height={w} rx={w / 2} />
    <rect x={x - w * 1.9} y={y + h / 2 - w} width={w * 3.8} height={w} rx={w / 2} />
  </g>
);

/** B: the text cursor jumps to where you look. */
export const CaretJump: React.FC<ConceptProps> = ({ small }) => (
  <Body id="caret" top="#2E3445" bottom="#10131A">
    <radialGradient id="caret-glow" cx="0.5" cy="0.5" r="0.5">
      <stop offset="0" stopColor={BLUE} stopOpacity="0.55" />
      <stop offset="1" stopColor={BLUE} stopOpacity="0" />
    </radialGradient>
    <circle cx={640} cy={512} r={260} fill="url(#caret-glow)" />
    {!small && (
      <>
        <path d="M300,430 C380,300 540,290 600,360" fill="none" stroke="#ffffff" strokeOpacity="0.35" strokeWidth="14"
          strokeLinecap="round" strokeDasharray="2 34" />
        <Caret x={300} y={512} h={250} w={34} fill="#ffffff" opacity={0.12} />
        <Caret x={450} y={512} h={250} w={34} fill="#ffffff" opacity={0.28} />
      </>
    )}
    <Caret x={small ? 512 : 640} y={512} h={small ? 420 : 330} w={small ? 64 : 46} fill="url(#caret-blue)" />
  </Body>
);

/** C: a head, seen from above, turned toward the lit screen in an arc of three. */
export const HeadTurn: React.FC<ConceptProps> = ({ small }) => {
  const cx = 512, cy = 660;
  const screens = [-38, 0, 38];
  const lit = 38;
  return (
    <Body id="head" top="#2E3445" bottom="#10131A">
      {/* line of sight */}
      <path d={`M${cx},${cy} L${cx + 260 * Math.sin((lit - 9) * Math.PI / 180)},${cy - 330 * Math.cos((lit - 9) * Math.PI / 180)} L${cx + 330 * Math.sin((lit + 9) * Math.PI / 180)},${cy - 330 * Math.cos((lit + 9) * Math.PI / 180)} Z`}
        fill={BLUE} opacity={0.28} />
      {screens.map((a) => {
        if (small && a !== lit && a !== 0) return null;
        const r = 330;
        const x = cx + r * Math.sin((a * Math.PI) / 180);
        const y = cy - r * Math.cos((a * Math.PI) / 180);
        return (
          <rect key={a} x={x - 115} y={y - 26} width={230} height={52} rx={26}
            transform={`rotate(${a} ${x} ${y})`} fill={a === lit ? "url(#head-blue)" : "#4A5268"} />
        );
      })}
      {/* head: circle with a nose pointing at the lit screen */}
      <g transform={`rotate(${lit} ${cx} ${cy})`} fill="#E7E9EA">
        <ellipse cx={cx - 108} cy={cy + 4} rx={24} ry={44} />
        <ellipse cx={cx + 108} cy={cy + 4} rx={24} ry={44} />
        <path d={`M${cx - 44},${cy - 92} Q${cx},${cy - 178} ${cx + 44},${cy - 92} Z`} />
        <ellipse cx={cx} cy={cy} rx={small ? 120 : 106} ry={small ? 130 : 116} />
      </g>
    </Body>
  );
};

/** D: a bold "S" drawn as one line of sight between two points. */
export const Monogram: React.FC<ConceptProps> = ({ small }) => (
  <Body id="mono" top="#41B4FF" bottom="#0C6FC0">
    <path d="M660,330 C640,270 590,250 512,250 C410,250 350,300 350,380 C350,470 430,495 512,512 C600,530 674,555 674,644 C674,724 614,774 512,774 C434,774 384,754 364,694"
      fill="none" stroke="#ffffff" strokeWidth={small ? 120 : 96} strokeLinecap="round" />
    {!small && (
      <>
        <circle cx={660} cy={330} r={34} fill="#0C6FC0" />
        <circle cx={364} cy={694} r={34} fill="#0C6FC0" />
      </>
    )}
  </Body>
);

/** E: the thing in focus, inside fading focus rings, on a light body. */
export const Focus: React.FC<ConceptProps> = ({ small }) => (
  <Body id="focus" top="#FFFFFF" bottom="#DCE6F0">
    {!small && (
      <>
        <rect x={232} y={232} width={560} height={560} rx={150} fill="none" stroke={BLUE} strokeOpacity="0.14" strokeWidth="22" />
        <rect x={302} y={302} width={420} height={420} rx={116} fill="none" stroke={BLUE} strokeOpacity="0.32" strokeWidth="22" />
      </>
    )}
    <rect x={small ? 262 : 372} y={small ? 262 : 372} width={small ? 500 : 280} height={small ? 500 : 280}
      rx={small ? 130 : 78} fill="url(#focus-blue)" />
    <Caret x={512} y={512} h={small ? 260 : 150} w={small ? 46 : 28} fill="#ffffff" />
  </Body>
);

const PanelsConcept: React.FC<ConceptProps> = ({ small }) => (
  <Icon bodyTop="#3A4259" bodyBottom="#151922" glowTop={BLUE_LIGHT} glowBottom={BLUE} small={small} />
);

export const CONCEPTS: { id: string; name: string; idea: string; Component: React.FC<ConceptProps> }[] = [
  { id: "A", name: "Panels", idea: "Two screens; a cone of sight lights the one you face.", Component: PanelsConcept },
  { id: "B", name: "Caret Jump", idea: "The text cursor jumps to where you look.", Component: CaretJump },
  { id: "C", name: "Head Turn", idea: "Your head, from above, turned to the lit screen.", Component: HeadTurn },
  { id: "D", name: "Monogram", idea: "An S drawn as one line of sight.", Component: Monogram },
  { id: "E", name: "Focus", idea: "The window in focus, inside focus rings.", Component: Focus },
];

const Scaled: React.FC<{ size: number; small: boolean; C: React.FC<ConceptProps> }> = ({ size, small, C }) => (
  <div style={{ width: size, height: size, position: "relative", overflow: "hidden", flex: "none" }}>
    <div style={{ width: 1024, height: 1024, scale: String(size / 1024), transformOrigin: "0 0", position: "absolute" }}>
      <C small={small} />
    </div>
  </div>
);

const Sizes: React.FC<{ C: React.FC<ConceptProps>; bg: string }> = ({ C, bg }) => (
  <div style={{ background: bg, borderRadius: 18, padding: "18px 26px", display: "flex", alignItems: "center", gap: 30 }}>
    <Scaled size={200} small={false} C={C} />
    <Scaled size={96} small={false} C={C} />
    <Scaled size={48} small={false} C={C} />
    <Scaled size={32} small={true} C={C} />
    <Scaled size={16} small={true} C={C} />
  </div>
);

/** Every concept at Dock, Finder and list sizes, on light and dark, to choose from. */
export const LogoLab: React.FC = () => (
  <AbsoluteFill style={{ background: "#F7F8F8", fontFamily, padding: 48, display: "flex", flexDirection: "column", gap: 22 }}>
    <div style={{ fontSize: 34, fontWeight: 700, color: "#0F1419", letterSpacing: -0.8 }}>Sightline logo concepts</div>
    {CONCEPTS.map(({ id, name, idea, Component }) => (
      <div key={id} style={{ display: "flex", alignItems: "center", gap: 28 }}>
        <div style={{ width: 230, flex: "none" }}>
          <div style={{ fontSize: 15, fontWeight: 700, color: BLUE }}>{id}</div>
          <div style={{ fontSize: 24, fontWeight: 700, color: "#0F1419" }}>{name}</div>
          <div style={{ fontSize: 15, color: "#52585D", lineHeight: 1.35, marginTop: 4 }}>{idea}</div>
        </div>
        <Sizes C={Component} bg="#E9EDF1" />
        <Sizes C={Component} bg="#17181C" />
      </div>
    ))}
  </AbsoluteFill>
);
