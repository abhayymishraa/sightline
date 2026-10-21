import { Folder, Still } from "remotion";
import { Icon } from "./Icon";
import { Preview } from "./Preview";
import { Banner } from "./Banner";
import { CaretJump, Focus, HeadTurn, LogoLab, Monogram } from "./Concepts";

export const RemotionRoot: React.FC = () => {
  return (
    <>
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
    <Folder name="Concepts">
      <Still id="LogoLab" component={LogoLab} width={1500} height={1460} />
      <Still id="ConceptB" component={CaretJump} width={1024} height={1024} defaultProps={{ small: false }} />
      <Still id="ConceptC" component={HeadTurn} width={1024} height={1024} defaultProps={{ small: false }} />
      <Still id="ConceptD" component={Monogram} width={1024} height={1024} defaultProps={{ small: false }} />
      <Still id="ConceptE" component={Focus} width={1024} height={1024} defaultProps={{ small: false }} />
    </Folder>
    </>
  );
};
