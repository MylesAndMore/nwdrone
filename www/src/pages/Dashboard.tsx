import { useEffect, useState } from "preact/hooks";

import ContentBlock from "../elements/ContentBlock";

import { socket } from "../helpers/socket";

export default function Dashboard() {
    const [thrust, setThrust] = useState<number>(0);

    const sendThrust = () => {
        const thrustData = { cmp: "thrust", dat: [{ value: thrust }] };
        socket.send(thrustData);
    };

    useEffect(() => {
        // Socket has already been opened in Index so no need to do that here
        // But, we should close the socket when the component is unmounted (user leaves the page)
        return () => socket.close();
    }, []);

    return (
        <ContentBlock title="Dashboard">
            <div className="text-center">
                <h1 className="text-white text-4xl font-bold">
                    epic ui comes soon(tm)
                </h1>
                <div className="mt-4">
                    <input
                        type="number"
                        value={thrust}
                        onChange={e =>
                            setThrust(
                                Number((e.target as HTMLInputElement).value),
                            )
                        }
                        className="border rounded p-2"
                        placeholder="Set Thrust"
                    />
                    <button
                        onClick={sendThrust}
                        className="ml-2 p-2 bg-blue-500 text-white rounded"
                    >
                        Set Thrust
                    </button>
                </div>
            </div>
        </ContentBlock>
    );
}
