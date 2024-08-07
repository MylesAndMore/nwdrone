interface SocketData {
    cmp: string; // Component; component that the data applies to, such as `led`, `btn`, etc.
    dat: Array<{ [key: string]: any }>; // Data; array of key-value pairs, for example {"status":1},{"client":"mom"} etc.
}

// Callback type for subscribers to the websocket.
type Callback = (data: SocketData) => void;

class Socket {
    private socket: WebSocket | null = null;
    private subscribers: Map<string, Callback[]> = new Map(); // Map of component names to subscriber callbacks

    /**
     * Open a websocket connection.
     * @param onOpen callback to run if the connection successfully opens
     * @param url url to connect to, defaults to the current host
     */
    open(
        onOpen?: () => void,
        url = `${window.location.protocol === "https:" ? "wss" : "ws"}://${window.location.host}/ws`,
    ): void {
        if (this.socket) {
            return;
        }
        this.socket = new WebSocket(url);

        this.socket.onopen = () => {
            if (onOpen) {
                onOpen();
            }
        };

        this.socket.onmessage = event => {
            const data = JSON.parse(event.data as string) as SocketData;
            this.notifySubscribers(data);
        };

        this.socket.onclose = () => {
            this.socket = null;
        };

        this.socket.onerror = error => {
            console.error("socket error: ", error);
        };
    }

    /**
     * Close the websocket connection.
     */
    close(): void {
        if (this.socket) {
            this.socket.close();
        }
    }

    /**
     * Send data over the websocket connection.
     * @param data `SocketData` to send
     */
    send(data: SocketData): void {
        if (this.socket && this.socket.readyState === WebSocket.OPEN) {
            this.socket.send(JSON.stringify(data));
        } else {
            console.error("socket is not open");
        }
    }

    /**
     * Register a callback to be called when data is received for a specific component.
     * @param component component name to subscribe to
     * @param callback callback to run when data is received
     */
    subscribe(component: string, callback: Callback): void {
        if (!this.subscribers.has(component)) {
            this.subscribers.set(component, []);
        }
        this.subscribers.get(component)?.push(callback);
    }

    /**
     * Unregister a callback for a specific component.
     * @param component component name to unsubscribe from
     * @param callback callback to remove
     */
    unsubscribe(component: string, callback: Callback): void {
        const callbacks = this.subscribers.get(component);
        if (callbacks) {
            this.subscribers.set(
                component,
                callbacks.filter(cb => cb !== callback),
            );
        }
    }

    /**
     * Notify all relavent subscribers of new data.
     * @param data new data to send to subscribers
     */
    private notifySubscribers(data: SocketData): void {
        const callbacks = this.subscribers.get(data.cmp);
        if (callbacks) {
            callbacks.forEach(callback => callback(data));
        }
    }
}

// Global socket instance
export const socket = new Socket();
