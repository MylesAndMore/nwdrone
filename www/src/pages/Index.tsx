import { useEffect, useState } from "preact/hooks";
import { Redirect } from "wouter-preact";

import Spinner from "../elements/Spinner";

import { socket } from "../helpers/socket";

export default function Index() {
    const [loading, setLoading] = useState(true);

    useEffect(() => {
        // Try opening socket on page load to make sure it's working
        // If successful, we will redirect to dashboard
        socket.open(() => setLoading(false));
    }, []);

    return (
        <div className="w-full h-full items-center justify-center">
            {loading ? <Spinner /> : <Redirect to="/dashboard" />}
        </div>
    );
}
