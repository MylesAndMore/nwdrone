import { render } from "preact";
import { useEffect } from "preact/hooks";
import { Link, Route, Switch } from "wouter-preact";

import Actions from "./pages/Actions";
import Dashboard from "./pages/Dashboard";
import Index from "./pages/Index";

import { socket } from "./helpers/socket";

import "./style.css";

// 404 page
function NoMatch() {
    return (
        <div className="flex flex-col items-center justify-center h-screen">
            <h2 className="text-4xl font-bold mb-4 text-gray-300">
                <span className="text-pink-600">(404)</span> Nothing to see
                here!
            </h2>
            <p>
                <Link
                    to="/"
                    className="text-blue-600 hover:text-sky-500 hover:underline"
                >
                    Return to the home page
                </Link>
            </p>
        </div>
    );
}

function App() {
    useEffect(() => {
        // Open socket connection on page load, close on unload
        socket.open();
        return () => socket.close();
    }, []);

    return (
        <main class={"w-full h-full"}>
            <Switch>
                <Route path="/">{() => <Index />}</Route>
                <Route path="/actions">{() => <Actions />}</Route>
                <Route path="/dashboard">{() => <Dashboard />}</Route>
                <Route>{() => <NoMatch />}</Route>
            </Switch>
        </main>
    );
}

render(<App />, document.getElementById("root"));
