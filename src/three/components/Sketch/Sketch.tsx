import type { Group } from 'three'
import RES from '@/three/RES'
import { Clone, Environment, OrbitControls, useCubeTexture, useGLTF } from '@react-three/drei'
import { useThree } from '@react-three/fiber'
import { useInteractStore, useLoadedStore } from '@utils/Store'
import { useEffect, useRef } from 'react'
import { Mesh, PMREMGenerator, ShaderMaterial, Uniform } from 'three'
import fragmentShader from './shaders/fragment.glsl'
import vertexShader from './shaders/vertex.glsl'

function Sketch() {
  const envMap = useCubeTexture([
    ...RES.cubeTexture,
  ], { path: '' })

  const gltf = useGLTF(RES.model.damagedHelemt)

  const controlDom = useInteractStore(state => state.controlDom)

  const gl = useThree(state => state.gl)

  const cloneRef = useRef<Group>(null)

  useEffect(() => {
    const pmremGenerator = new PMREMGenerator(gl)

    const rt = pmremGenerator.fromCubemap(envMap)

    const cloneGroup = cloneRef.current!
    cloneGroup.traverse((child) => {
      if (child instanceof Mesh) {
        const oldMat = child.material

        child.material = new ShaderMaterial({
          defines: {
            ENVMAP_TYPE_CUBE_UV: true,
            CUBEUV_TEXEL_WIDTH: 1 / rt.texture.image.width,
            CUBEUV_TEXEL_HEIGHT: 1 / rt.texture.image.height,
            CUBEUV_MAX_MIP: `${
              Math.log2(rt.texture.image.height) - 2
            }.0`,
          },
          uniforms: {
            map: new Uniform(oldMat.map),
            metalnessMap: new Uniform(oldMat.metalnessMap),
            roughnessMap: new Uniform(oldMat.roughnessMap),
            emisssiveMap: new Uniform(oldMat.emissiveMap),
            normalMap: new Uniform(oldMat.normalMap),
            aoMap: new Uniform(oldMat.aoMap),
            envMap: new Uniform(rt.texture),
            intensity: new Uniform(2),
          },
          vertexShader,
          fragmentShader,
        })
      }
    })
    useLoadedStore.setState({ ready: true })
  }, [envMap])

  return (
    <>
      <OrbitControls domElement={controlDom} />
      <ambientLight intensity={2} />
      <color attach="background" args={['black']} />
      <primitive object={gltf.scene} position={[1, 0, 0]} />
      <Clone object={gltf.scene} position={[-1, 0, 0]} ref={cloneRef} />
      <Environment map={envMap} background />
    </>
  )
}

export default Sketch
