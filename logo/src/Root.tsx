import { Folder, Still } from "remotion";
import { Icon } from "./Icon";
import { Preview } from "./Preview";
import { Banner } from "./Banner";

export const RemotionRoot: React.FC = () => {
  return (
    <Folder name="AppIcon">
      <Still
        id="Icon"
        component={Icon}
        width={1024}
        height={1024}
        defaultProps={{ bodyTop: "#3A4259", bodyBottom: "#151922", glowTop: "#7CCBFF", glowBottom: "#1C9CF0", small: false }}
      />
      <Still
        id="IconSmall"
        component={Icon}
        width={1024}
        height={1024}
        defaultProps={{ bodyTop: "#3A4259", bodyBottom: "#151922", glowTop: "#7CCBFF", glowBottom: "#1C9CF0", small: true }}
      />
      <Still
        id="Preview"
        component={Preview}
        width={1200}
        height={720}
        defaultProps={{ bodyTop: "#3A4259", bodyBottom: "#151922", glowTop: "#7CCBFF", glowBottom: "#1C9CF0", small: false }}
      />
      <Still
        id="Banner"
        component={Banner}
        width={1280}
        height={640}
        defaultProps={{ bodyTop: "#3A4259", bodyBottom: "#151922", glowTop: "#7CCBFF", glowBottom: "#1C9CF0", small: false }}
      />
    </Folder>
  );
};
