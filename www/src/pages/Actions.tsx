import ContentBlock from "../elements/ContentBlock";
import { socket } from "../helpers/socket";

export default function Actions() {
    return (
        <ContentBlock title="Actions">
            <div className="flex justify-center items-center m-4 h-screen space-x-2">
                <button
                    onClick={() => socket.send({ event: "kill", data: {} })}
                    className="p-2 bg-red-500 text-white rounded"
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
                <button
                    onClick={() => socket.send({ event: "takeoff", data: {} })}
                    className="p-2 bg-green-600 text-white rounded"
                    title="Take off the drone"
                >
                    Takeoff
                </button>
                <button
                    onClick={() => socket.send({ event: "land", data: {} })}
                    className="p-2 bg-blue-500 text-white rounded"
                    title="Land the drone"
                >
                    Land
                </button>
            </div>
        </ContentBlock>
    );
}
