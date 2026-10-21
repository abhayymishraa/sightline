import React from "react";
import { AbsoluteFill } from "remotion";
import { loadFont } from "@remotion/google-fonts/Geist";
import { Icon, type IconProps } from "./Icon";

const { fontFamily } = loadFont("normal", { weights: ["400", "500", "700"], subsets: ["latin"] });

/** README header and GitHub social preview (1280 × 640). */
export const Banner: React.FC<IconProps> = (props) => (
  <AbsoluteFill
    style={{
      background: "radial-gradient(1200px 600px at 78% 40%, #0B2236 0%, #07090D 55%, #040506 100%)",
      fontFamily,
      color: "#E7E9EA",
      display: "flex",
      flexDirection: "row",
      alignItems: "center",
      padding: "0 96px",
      gap: 40,
    }}
  >
    <div style={{ flex: 1, display: "flex", flexDirection: "column", gap: 22 }}>
      <div style={{ fontSize: 30, fontWeight: 500, color: "#1C9CF0", letterSpacing: -0.2 }}>Sightline</div>
      <div style={{ fontSize: 76, fontWeight: 700, lineHeight: 1.02, letterSpacing: -2.4 }}>
        Type where
        <br />
        you look.
      </div>
      <div style={{ fontSize: 26, color: "#9AA0A6", lineHeight: 1.4, maxWidth: 560 }}>
        Your webcam moves keyboard focus to the screen you face. Free and open source, for macOS and Windows.
      </div>
    </div>
    <div style={{ width: 440, height: 440, position: "relative" }}>
      <div style={{ width: 1024, height: 1024, scale: String(440 / 1024), transformOrigin: "0 0", position: "absolute" }}>
        <Icon {...props} />
      </div>
    </div>
  </AbsoluteFill>
);
