import ContentBlock from "../elements/ContentBlock";

import { socket } from "../helpers/socket";

export default function Actions() {
    return (
        <ContentBlock title="Actions">
            <div className="flex justify-center items-center m-4 h-screen">
                <button
                    onClick={() => socket.send({ event: "kill", data: {} })}
                    className="mr-2 p-2 bg-red-500 text-white rounded"
                    title="Kill the drone's backing process"
                >
                    Kill
                </button>
                <button
                    onClick={() => socket.send({ event: "shutdown", data: {} })}
                    className="p-2 bg-orange-500 text-white rounded"
                    title="Shut down the drone"
                >
                    Shutdown
                </button>
            </div>
        </ContentBlock>
    );
}
