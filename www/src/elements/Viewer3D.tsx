import * as THREE from "three";
import preact from "preact";
import { useEffect, useRef } from "preact/hooks";

import { socket } from "../helpers/socket";

const Viewer3D: preact.FunctionComponent = () => {
    const containerRef = useRef<HTMLDivElement>(null);
    const sceneRef = useRef<THREE.Scene>();
    const cameraRef = useRef<THREE.PerspectiveCamera>();
    const rendererRef = useRef<THREE.WebGLRenderer>();
    const cubeRef = useRef<THREE.Mesh>();

    useEffect(() => {
        // Set up the scene, camera, and renderer
        const scene = new THREE.Scene();
        sceneRef.current = scene;
        const camera = new THREE.PerspectiveCamera(75, 1, 0.1, 1000);
        camera.position.z = 5;
        cameraRef.current = camera;
        const renderer = new THREE.WebGLRenderer({ antialias: true });
        renderer.setSize(300, 300); // You can adjust this to fit your layout
        const container = containerRef.current;
        container?.appendChild(renderer.domElement);
        rendererRef.current = renderer;

        // Add a wireframe cube to the scene
        const geometry = new THREE.BoxGeometry();
        const material = new THREE.MeshBasicMaterial({
            color: 0x00ff00,
            wireframe: true,
        });
        const cube = new THREE.Mesh(geometry, material);
        scene.add(cube);
        cubeRef.current = cube;

        // Update cube rotation on orientation event
        socket.subscribe("orient", event => {
            if (!cubeRef.current) {
                return;
            }

            const { roll, pitch, yaw } = event.data;
            cubeRef.current.rotation.x = THREE.MathUtils.degToRad(pitch);
            cubeRef.current.rotation.y = THREE.MathUtils.degToRad(yaw);
            cubeRef.current.rotation.z = THREE.MathUtils.degToRad(roll);

            renderer.render(scene, camera);
        });

        return () => {
            // Clean up on unmount
            if (container) {
                container.removeChild(renderer.domElement);
            }
        };
    }, []);

    return <div ref={containerRef} />;
};

export default Viewer3D;
