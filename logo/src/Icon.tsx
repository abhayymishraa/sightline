import React from "react";
import { AbsoluteFill, Img, staticFile } from "remotion";

export type IconProps = {
  /** 16 and 32 px use the simplified art in public/icon-small.svg. */
  readonly small: boolean;
};

/** The app icon (concept 04, "Lit Pane"): two panes, and the one you face is lit and holds the caret.
 *  The art lives in public/icon.svg and public/icon-small.svg on Apple's 1024 grid (824 pt body). */
export const Icon: React.FC<IconProps> = ({ small }) => (
  <AbsoluteFill>
    <Img src={staticFile(small ? "icon-small.svg" : "icon.svg")} style={{ width: 1024, height: 1024 }} />
  </AbsoluteFill>
);
