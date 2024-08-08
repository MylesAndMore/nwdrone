// The type for data sent/received over the websocket.
// An equivalent type is defined in the server code (/src/remote/sockets.zig).
export interface SocketData {
    // Event that the data applies to, such as `thrust`, `shutdown`, etc.
    event: string;
    // Object containing string key-value pairs, for example {"status":"1", "client":"mom"} etc.
    data: { [key: string]: string };
}

// Callback type for subscribers to the websocket.
type Callback = (event: SocketData) => void;

class Socket {
    public isOpen = false; // Whether the socket is currently open
    private socket: WebSocket | null = null; // Backing websocket instance
    private subscribers: Map<string, Callback[]> = new Map(); // Map of event names to subscriber callbacks

    /**
     * Open a websocket connection.
     * @param url url to connect to, defaults to the current host
     */
    open(
        url = `${window.location.protocol === "https:" ? "wss" : "ws"}://${window.location.host}/ws`,
    ): void {
        if (this.socket) {
            return;
        }
        this.socket = new WebSocket(url);

        this.socket.onopen = () => {
            this.isOpen = true;
        };

        this.socket.onmessage = event => {
            console.log(`rx: ${event.data as string}`);
            const data = JSON.parse(event.data as string) as SocketData;
            this.notifySubscribers(data);
        };

        this.socket.onclose = () => {
            this.isOpen = false;
            this.socket = null;
            this.subscribers.clear(); // Unsubscribe all subscribers
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
            console.log(`tx: ${JSON.stringify(data)}`);
            this.socket.send(JSON.stringify(data));
        } else {
            console.error("socket is not open");
        }
    }

    /**
     * Register a callback to be called when data is received for a specific event.
     * @param event event name to subscribe to
     * @param callback callback to run when data is received
     */
    subscribe(event: string, callback: Callback): void {
        if (!this.subscribers.has(event)) {
            this.subscribers.set(event, []);
        }
        this.subscribers.get(event)?.push(callback);
    }

    /**
     * Unregister a callback for a specific event.
     * @param event event name to unsubscribe from
     * @param callback callback to remove
     */
    unsubscribe(event: string, callback: Callback): void {
        const callbacks = this.subscribers.get(event);
        if (callbacks) {
            this.subscribers.set(
                event,
                callbacks.filter(cb => cb !== callback),
            );
        }
    }

    /**
     * Notify all relavent subscribers of new data.
     * @param data new data to send to subscribers
     */
    private notifySubscribers(data: SocketData): void {
        const callbacks = this.subscribers.get(data.event);
        if (callbacks) {
            callbacks.forEach(callback => callback(data));
        }
    }
}

// Global socket instance
export const socket = new Socket();
