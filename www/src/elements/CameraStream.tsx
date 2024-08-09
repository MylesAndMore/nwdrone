import preact from "preact";
import { useEffect, useRef, useState } from "preact/hooks";

import { socket } from "../helpers/socket";

const FRAME_WIDTH = 320;
const FRAME_HEIGHT = 200;

interface CameraStreamProps {
    displayFps?: boolean;
}

/**
 * @param base64 base64 encoded string
 * @returns a Uint8Array representing the binary data of `base64`
 */
function base64ToUint8Array(base64: string): Uint8Array {
    const binary = atob(base64);
    const len = binary.length;
    const bytes = new Uint8Array(len);
    for (let i = 0; i < len; i++) {
        bytes[i] = binary.charCodeAt(i);
    }
    return bytes;
}

/**
 * Perform Bayer interpolation on a pixel.
 * @param width width of the frame
 * @param x x-coordinate of the pixel
 * @param y y-coordinate of the pixel
 * @param pixelIndex index of the pixel in the raw data
 * @param raw raw data of the frame
 * @returns RGB interpolated values of the pixel
 */
function interpolateBayer(
    width: number,
    x: number,
    y: number,
    pixelIndex: number,
    raw: Uint8Array,
): { r: number; g: number; b: number } {
    let r = 0,
        g = 0,
        b = 0;
    const pixel = raw[pixelIndex];

    if (y & 1) {
        if (x & 1) {
            r = pixel;
            g =
                (raw[pixelIndex - 1] +
                    raw[pixelIndex + 1] +
                    raw[pixelIndex + width] +
                    raw[pixelIndex - width]) >>
                2;
            b =
                (raw[pixelIndex - width - 1] +
                    raw[pixelIndex - width + 1] +
                    raw[pixelIndex + width - 1] +
                    raw[pixelIndex + width + 1]) >>
                2;
        } else {
            r = (raw[pixelIndex - 1] + raw[pixelIndex + 1]) >> 1;
            g = pixel;
            b = (raw[pixelIndex - width] + raw[pixelIndex + width]) >> 1;
        }
    } else if (x & 1) {
        r = (raw[pixelIndex - width] + raw[pixelIndex + width]) >> 1;
        g = pixel;
        b = (raw[pixelIndex - 1] + raw[pixelIndex + 1]) >> 1;
    } else {
        r =
            (raw[pixelIndex - width - 1] +
                raw[pixelIndex - width + 1] +
                raw[pixelIndex + width - 1] +
                raw[pixelIndex + width + 1]) >>
            2;
        g =
            (raw[pixelIndex - 1] +
                raw[pixelIndex + 1] +
                raw[pixelIndex + width] +
                raw[pixelIndex - width]) >>
            2;
        b = pixel;
    }

    return { r, g, b };
}

const CameraStream: preact.FunctionComponent<CameraStreamProps> = ({
    displayFps = false,
}) => {
    const canvas = useRef<HTMLCanvasElement>(null);
    const [fps, setFps] = useState(0);

    useEffect(() => {
        let lastFrameTime = performance.now();
        let frameCount = 0;

        socket.subscribe("frame", event => {
            if (!canvas.current) {
                return;
            }
            const ctx = canvas.current.getContext("2d");
            if (!ctx) {
                return;
            }

            const rawData = base64ToUint8Array(event.data.raw);
            const imageData = ctx.createImageData(FRAME_WIDTH, FRAME_HEIGHT);
            const rgbData = new Uint8ClampedArray(
                FRAME_WIDTH * FRAME_HEIGHT * 4,
            ); // RGBA
            // Interpolate RGB pixel data
            for (let y = 0; y < FRAME_HEIGHT; y++) {
                for (let x = 0; x < FRAME_WIDTH; x++) {
                    const pixelIndex = y * FRAME_WIDTH + x;
                    const { r, g, b } = interpolateBayer(
                        FRAME_WIDTH,
                        x,
                        y,
                        pixelIndex,
                        rawData,
                    );
                    const rgbIndex = pixelIndex * 4;
                    rgbData[rgbIndex] = r;
                    rgbData[rgbIndex + 1] = g;
                    rgbData[rgbIndex + 2] = b;
                    rgbData[rgbIndex + 3] = 255; // Alpha channel
                }
            }
            // Render on canvas
            imageData.data.set(rgbData);
            ctx.putImageData(imageData, 0, 0);

            // Calculate and display FPS
            frameCount++;
            const now = performance.now();
            const delta = now - lastFrameTime;
            if (delta >= 1000) {
                const currentFps = Math.round((frameCount * 1000) / delta);
                setFps(currentFps);
                frameCount = 0;
                lastFrameTime = now;
            }
            if (displayFps) {
                ctx.fillStyle = "white";
                ctx.font = "16px Arial";
                ctx.fillText(`FPS: ${fps}`, FRAME_WIDTH - 60, 20);
            }
        });
    }, [fps]);

    return (
        <canvas
            className="md:w-[640px] md:h-[400px]"
            ref={canvas}
            width="320"
            height="200"
        />
    );
};

export default CameraStream;
