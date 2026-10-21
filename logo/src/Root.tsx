import { Folder, Still } from "remotion";
import { Banner } from "./Banner";
import { Icon } from "./Icon";
import { Preview } from "./Preview";

export const RemotionRoot: React.FC = () => {
  return (
    <Folder name="AppIcon">
      <Still id="Icon" component={Icon} width={1024} height={1024} defaultProps={{ small: false }} />
      <Still id="IconSmall" component={Icon} width={1024} height={1024} defaultProps={{ small: true }} />
      <Still id="Preview" component={Preview} width={1200} height={720} defaultProps={{ small: false }} />
      <Still id="Banner" component={Banner} width={1280} height={640} defaultProps={{ small: false }} />
    </Folder>
  );
};
