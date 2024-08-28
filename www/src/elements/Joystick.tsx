import nipplejs from "nipplejs";
import { useEffect, useRef } from "preact/hooks";

import { socket } from "../helpers/socket";

const Joystick = () => {
    const joystickRef = useRef<HTMLDivElement>(null);

    useEffect(() => {
        const joystick = nipplejs.create({
            zone: joystickRef.current,
            mode: "static",
            position: { left: "50%" },
            color: "white",
        });

        joystick.on("move", (event, data) => {
            const { angle, distance } = data;
            const maxDist = 50;
            const normalizedDist = (distance / maxDist) * 2; // Normalize to range -2 to 2
            const roll = Math.cos(angle.radian) * normalizedDist;
            const pitch = Math.sin(angle.radian) * normalizedDist;
            socket.send({
                event: "move",
                data: { roll: roll.toFixed(3), pitch: pitch.toFixed(3) },
            });
        });

        joystick.on("end", () => {
            socket.send({ event: "move", data: { roll: "0", pitch: "0" } });
        });

        return () => joystick.destroy();
    }, []);

    return (
        <div
            ref={joystickRef}
            style={{ width: "100%", height: "100vh", position: "relative" }}
        />
    );
};

export default Joystick;
