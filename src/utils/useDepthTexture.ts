import type { Texture } from 'three'
import { useFBO } from '@react-three/drei'
import { useFrame, useThree } from '@react-three/fiber'
import { useMemo } from 'react'
import { DepthFormat, DepthTexture, RGBAFormat, ShaderMaterial, Uniform, UnsignedShortType } from 'three'
import { FullScreenQuad } from 'three/examples/jsm/Addons.js'

function useDepthTexture(width: number, height: number) {
  const camera = useThree(state => state.camera)

  const rt1 = useFBO(width, height, {
    depthBuffer: true,
    stencilBuffer: false,
    depthTexture: new DepthTexture(width, height),
    generateMipmaps: false,
    format: RGBAFormat,
  })
  rt1.depthTexture.format = DepthFormat
  rt1.depthTexture.type = UnsignedShortType

  const rt2 = useFBO(width, height, {
    depthBuffer: false,
    stencilBuffer: false,
    generateMipmaps: false,
    samples: 16,
    format: RGBAFormat,
  })

  const uniforms = useMemo(() => ({
    tDiffuse: new Uniform(rt1.texture),
    tDepth: new Uniform(rt1.depthTexture),
    cameraNear: new Uniform(1),
    cameraFar: new Uniform(10),
  }), [])

  const material = useMemo(() => new ShaderMaterial({
    vertexShader: /* glsl */`
    varying vec2 vUv;
    void main() {
      vUv = uv;
      gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0);
    }
    `,
    fragmentShader: /* glsl */`
    #include <packing>

    varying vec2 vUv;
    uniform sampler2D tDiffuse;
    uniform sampler2D tDepth;
    uniform float cameraNear;
    uniform float cameraFar;
    
    float readDepth(sampler2D depthSampler, vec2 coord) {
      float fragCoordZ = texture2D(depthSampler, coord).x;
      float viewZ = perspectiveDepthToViewZ(fragCoordZ, cameraNear, cameraFar);
      return viewZToOrthographicDepth(viewZ, cameraNear, cameraFar);
    }
    
    void main() {
      // vec3 diffuse = texture2D(tDiffuse, vUv).rgb;
      float depth = readDepth(tDepth, vUv);
      gl_FragColor.rgb = 1.0 - vec3(depth);
      gl_FragColor.a = 1.0;
    }
    `,
    uniforms,
  }), [])

  const fullScreenQuad = useMemo(() => new FullScreenQuad(material), [])

  useFrame((state, delta) => {
    const { gl, scene } = state
    const dpr = gl.getPixelRatio()
    rt1.setSize(innerWidth * dpr, innerHeight * dpr)
    rt2.setSize(innerWidth * dpr, innerHeight * dpr)
    gl.setRenderTarget(rt1)
    gl.render(scene, camera)
    gl.setRenderTarget(rt2)
    uniforms.tDepth.value = rt1.depthTexture
    uniforms.tDiffuse.value = rt1.texture
    fullScreenQuad.render(gl)
    gl.setRenderTarget(null)
  })

  return { depthTexture: rt2.texture as Texture }
}

export {
  useDepthTexture,
}
