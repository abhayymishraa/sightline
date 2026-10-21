import React from "react";
import { AbsoluteFill } from "remotion";
import { Icon, type IconProps } from "./Icon";

/** The icon at Dock, Finder and list sizes on light and dark backgrounds, for review only. */
const Scaled: React.FC<{ readonly size: number; readonly props: IconProps }> = ({ size, props }) => (
  <div style={{ width: size, height: size, position: "relative", overflow: "hidden" }}>
    <div style={{ width: 1024, height: 1024, scale: String(size / 1024), transformOrigin: "0 0", position: "absolute" }}>
      <Icon {...props} />
    </div>
  </div>
);

const Row: React.FC<{ readonly bg: string; readonly props: IconProps }> = ({ bg, props }) => (
  <div style={{ flex: 1, background: bg, display: "flex", alignItems: "center", justifyContent: "center", gap: 56 }}>
    <Scaled size={256} props={props} />
    <Scaled size={128} props={props} />
    <Scaled size={64} props={props} />
    <Scaled size={32} props={{ ...props, small: true }} />
    <Scaled size={16} props={{ ...props, small: true }} />
  </div>
);

export const Preview: React.FC<IconProps> = (props) => (
  <AbsoluteFill style={{ display: "flex", flexDirection: "column" }}>
    <Row bg="#ECEEF1" props={props} />
    <Row bg="#1C1E22" props={props} />
  </AbsoluteFill>
);
