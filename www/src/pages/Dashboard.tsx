import CameraStream from "../elements/CameraStream";
import ContentBlock from "../elements/ContentBlock";
import Viewer3D from "../elements/Viewer3D";

export default function Dashboard() {
    return (
        <ContentBlock title="Dashboard">
            <CameraStream />
            <Viewer3D />
        </ContentBlock>
    );
}
