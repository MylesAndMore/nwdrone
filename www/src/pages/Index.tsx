import { useEffect, useState } from "preact/hooks";
import { Redirect } from "wouter-preact";

import Spinner from "../elements/Spinner";

import { socket } from "../helpers/socket";

export default function Index() {
    const [loading, setLoading] = useState(true);

    // Continuously check if the socket is open
    const checkSocketOpen = () => {
        if (socket.isOpen) {
            setLoading(false);
        } else {
            setTimeout(checkSocketOpen, 500);
        }
    };

    useEffect(() => {
        // Wait until socket successfully opens (the opening process is started in main.tsx)
        // If successful, we will redirect to dashboard
        checkSocketOpen();
    }, []);

    return (
        <div className="w-full h-full items-center justify-center">
            {loading ? <Spinner /> : <Redirect to="/dashboard" />}
        </div>
    );
}
