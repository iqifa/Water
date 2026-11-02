using System;
using UnityEngine;

[RequireComponent(typeof(MeshFilter), typeof(MeshRenderer))]
public class SineWater : MonoBehaviour {

    [Header("Mesh Settings")]
    public int planeSize = 10;
    public int resolution = 50;

    [Header("Wave Mode")]
    public bool useFBM = true;

    [Header("Discrete Wave Settings (FBM OFF)")]
    [Range(1, 64)]
    public int discreteWaveCount = 8;
    [Range(0.1f, 10f)]
    public float medianWavelength = 2.0f;
    [Range(0f, 1f)]
    public float wavelengthRange = 0.5f;
    [Range(0f, 360f)]
    public float medianDirection = 0f;
    [Range(0f, 360f)]
    public float directionalRange = 180f;
    [Range(0f, 2f)]
    public float medianAmplitude = 0.5f;
    [Range(0f, 5f)]
    public float medianSpeed = 1.0f;
    [Range(0f, 2f)]
    public float speedRange = 0.3f;

    [Header("FBM Vertex Settings (FBM ON)")]
    [Range(1, 64)]
    public int vertexWaveCount = 8;
    public float vertexSeed = 42f;
    public float vertexSeedIter = 1253.2131f;
    [Range(0.1f, 10f)]
    public float vertexFrequency = 1.0f;
    [Range(1.0f, 2.0f)]
    public float vertexFrequencyMult = 1.18f;
    [Range(0f, 5f)]
    public float vertexAmplitude = 1.0f;
    [Range(0.1f, 1.0f)]
    public float vertexAmplitudeMult = 0.82f;
    [Range(0f, 5f)]
    public float vertexMaxPeak = 1.0f;
    [Range(0f, 3f)]
    public float vertexPeakOffset = 1.0f;
    [Range(0f, 10f)]
    public float vertexInitialSpeed = 2.0f;
    [Range(1.0f, 2.0f)]
    public float vertexSpeedRamp = 1.07f;
    [Range(0f, 3f)]
    public float vertexDrag = 1.0f;
    [Range(0f, 5f)]
    public float vertexHeight = 1.0f;

    [Header("FBM Fragment Settings (FBM ON)")]
    [Range(1, 64)]
    public int fragmentWaveCount = 40;
    public float fragmentSeed = 100f;
    public float fragmentSeedIter = 1253.2131f;
    [Range(0.1f, 20f)]
    public float fragmentFrequency = 1.0f;
    [Range(1.0f, 2.0f)]
    public float fragmentFrequencyMult = 1.18f;
    [Range(0f, 5f)]
    public float fragmentAmplitude = 1.0f;
    [Range(0.1f, 1.0f)]
    public float fragmentAmplitudeMult = 0.82f;
    [Range(0f, 5f)]
    public float fragmentMaxPeak = 0.8f;
    [Range(0f, 3f)]
    public float fragmentPeakOffset = 1.0f;
    [Range(0f, 10f)]
    public float fragmentInitialSpeed = 2.0f;
    [Range(1.0f, 2.0f)]
    public float fragmentSpeedRamp = 1.07f;
    [Range(0f, 3f)]
    public float fragmentDrag = 1.0f;
    [Range(0f, 5f)]
    public float fragmentHeight = 1.0f;
    [Range(0f, 5f)]
    public float normalStrength = 1.2f;

    [Header("Material Settings")]
    public Color fresnelColor = new Color(0.7f, 0.85f, 0.95f, 1f);
    [Range(1f, 10f)]
    public float fresnelPower = 5.0f;
    [Range(0f, 1f)]
    public float smoothness = 0.9f;
    [Range(0f, 5f)]
    public float specularStrength = 1.0f;

    [Header("Foam Settings (浪尖白沫)")]
    public Color tipColor = new Color(1f, 1f, 1f, 1f);
    [Range(-1f, 1f)]
    public float tipThreshold = 0.5f;
    [Range(0.01f, 1f)]
    public float tipSpread = 0.2f;

    [Header("Underwater Settings (水下与折射)")]
    public Color shallowColor = new Color(0.3f, 0.7f, 0.8f, 1f);
    public Color deepColor = new Color(0.05f, 0.15f, 0.35f, 1f);
    [Range(0.01f, 2.0f)]
    public float depthDensity = 0.3f;
    [Range(0f, 0.2f)]
    public float refractionStrength = 0.02f;

    [Header("Shader")]
    public Shader waterShader;

    // Private variables
    private Material waterMaterial;
    private Mesh mesh;
    private ComputeBuffer waveBuffer;
    private Wave[] waves;

    [Serializable]
    public struct Wave {
        public Vector2 direction;
        public Vector2 origin;
        public float frequency;
        public float amplitude;
        public float phase;
        public float steepness;
        public int waveType;

        public Wave(float wavelength, float amplitude, float speed, float directionDegrees) {
            this.frequency = 2.0f * Mathf.PI / wavelength;
            this.amplitude = amplitude;
            this.phase = speed * Mathf.Sqrt(9.8f * 2.0f * Mathf.PI / wavelength);
            this.steepness = 1.0f;
            this.waveType = 0; // Directional
            this.origin = Vector2.zero;

            float rad = directionDegrees * Mathf.Deg2Rad;
            this.direction = new Vector2(Mathf.Cos(rad), Mathf.Sin(rad)).normalized;
        }
    }

    void OnEnable() {
        CreateWaterMesh();
        CreateMaterial();
        GenerateWaves();
    }

    void CreateWaterMesh() {
        mesh = new Mesh();
        mesh.name = "SineWater";

        int vertexCount = (resolution + 1) * (resolution + 1);
        Vector3[] vertices = new Vector3[vertexCount];
        Vector2[] uvs = new Vector2[vertexCount];

        float halfSize = planeSize * 0.5f;

        for (int i = 0, z = 0; z <= resolution; z++) {
            for (int x = 0; x <= resolution; x++, i++) {
                float xPos = (float)x / resolution * planeSize - halfSize;
                float zPos = (float)z / resolution * planeSize - halfSize;
                vertices[i] = new Vector3(xPos, 0, zPos);
                uvs[i] = new Vector2((float)x / resolution, (float)z / resolution);
            }
        }

        int[] triangles = new int[resolution * resolution * 6];
        for (int ti = 0, vi = 0, z = 0; z < resolution; z++, vi++) {
            for (int x = 0; x < resolution; x++, ti += 6, vi++) {
                triangles[ti] = vi;
                triangles[ti + 1] = vi + resolution + 1;
                triangles[ti + 2] = vi + 1;
                triangles[ti + 3] = vi + 1;
                triangles[ti + 4] = vi + resolution + 1;
                triangles[ti + 5] = vi + resolution + 2;
            }
        }

        mesh.vertices = vertices;
        mesh.uv = uvs;
        mesh.triangles = triangles;
        mesh.RecalculateNormals();
        mesh.RecalculateBounds();

        GetComponent<MeshFilter>().mesh = mesh;
    }

    void CreateMaterial() {
        if (waterShader == null) {
            // Force URP shader
            waterShader = Shader.Find("Custom/SineWaterURP");
            if (waterShader == null) {
                Debug.LogError("❌ Custom/SineWaterURP not found! Checking if shader file exists...");
                // Try built-in as last resort
                waterShader = Shader.Find("Custom/SineWater");
                if (waterShader != null) {
                    Debug.LogWarning("⚠️ Using old Built-in shader! This won't work in URP. Please manually assign SineWaterURP shader.");
                }
            } else {
                Debug.Log("✓ Found URP Shader: Custom/SineWaterURP");
            }
        }

        if (waterShader != null) {
            waterMaterial = new Material(waterShader);
            GetComponent<MeshRenderer>().material = waterMaterial;
            Debug.Log($"🌊 Water material created with shader: {waterShader.name}");
        } else {
            Debug.LogError("❌ No water shader found! Please assign SineWaterURP.shader manually in the Inspector.");
        }
    }

    public void GenerateWaves() {
        if (waves == null || waves.Length != 64) {
            waves = new Wave[64];
        }

        float wavelengthMin = medianWavelength / (1.0f + wavelengthRange);
        float wavelengthMax = medianWavelength * (1.0f + wavelengthRange);
        float directionMin = medianDirection - directionalRange;
        float directionMax = medianDirection + directionalRange;
        float speedMin = Mathf.Max(0.01f, medianSpeed - speedRange);
        float speedMax = medianSpeed + speedRange;
        float ampOverLen = medianAmplitude / medianWavelength;

        for (int i = 0; i < discreteWaveCount; i++) {
            float wavelength = UnityEngine.Random.Range(wavelengthMin, wavelengthMax);
            float direction = UnityEngine.Random.Range(directionMin, directionMax);
            float amplitude = wavelength * ampOverLen;
            float speed = UnityEngine.Random.Range(speedMin, speedMax);

            waves[i] = new Wave(wavelength, amplitude, speed, direction);
        }

        UpdateWaveBuffer();
    }

    void UpdateWaveBuffer() {
        if (waveBuffer != null) {
            waveBuffer.Release();
        }

        waveBuffer = new ComputeBuffer(64, System.Runtime.InteropServices.Marshal.SizeOf(typeof(Wave)));
        waveBuffer.SetData(waves);

        if (waterMaterial != null) {
            waterMaterial.SetBuffer("_Waves", waveBuffer);
        }
    }

    void Update() {
        if (waterMaterial == null) return;

        // Update FBM toggle
        waterMaterial.SetFloat("_UseFBM", useFBM ? 1.0f : 0.0f);

        if (useFBM) {
            waterMaterial.EnableKeyword("USE_FBM");
        } else {
            waterMaterial.DisableKeyword("USE_FBM");
        }

        // Update discrete wave count
        waterMaterial.SetInt("_WaveCount", discreteWaveCount);

        // Update FBM Vertex parameters
        waterMaterial.SetInt("_VertexWaveCount", vertexWaveCount);
        waterMaterial.SetFloat("_VertexSeed", vertexSeed);
        waterMaterial.SetFloat("_VertexSeedIter", vertexSeedIter);
        waterMaterial.SetFloat("_VertexFrequency", vertexFrequency);
        waterMaterial.SetFloat("_VertexFrequencyMult", vertexFrequencyMult);
        waterMaterial.SetFloat("_VertexAmplitude", vertexAmplitude);
        waterMaterial.SetFloat("_VertexAmplitudeMult", vertexAmplitudeMult);
        waterMaterial.SetFloat("_VertexMaxPeak", vertexMaxPeak);
        waterMaterial.SetFloat("_VertexPeakOffset", vertexPeakOffset);
        waterMaterial.SetFloat("_VertexInitialSpeed", vertexInitialSpeed);
        waterMaterial.SetFloat("_VertexSpeedRamp", vertexSpeedRamp);
        waterMaterial.SetFloat("_VertexDrag", vertexDrag);
        waterMaterial.SetFloat("_VertexHeight", vertexHeight);

        // Update FBM Fragment parameters
        waterMaterial.SetInt("_FragmentWaveCount", fragmentWaveCount);
        waterMaterial.SetFloat("_FragmentSeed", fragmentSeed);
        waterMaterial.SetFloat("_FragmentSeedIter", fragmentSeedIter);
        waterMaterial.SetFloat("_FragmentFrequency", fragmentFrequency);
        waterMaterial.SetFloat("_FragmentFrequencyMult", fragmentFrequencyMult);
        waterMaterial.SetFloat("_FragmentAmplitude", fragmentAmplitude);
        waterMaterial.SetFloat("_FragmentAmplitudeMult", fragmentAmplitudeMult);
        waterMaterial.SetFloat("_FragmentMaxPeak", fragmentMaxPeak);
        waterMaterial.SetFloat("_FragmentPeakOffset", fragmentPeakOffset);
        waterMaterial.SetFloat("_FragmentInitialSpeed", fragmentInitialSpeed);
        waterMaterial.SetFloat("_FragmentSpeedRamp", fragmentSpeedRamp);
        waterMaterial.SetFloat("_FragmentDrag", fragmentDrag);
        waterMaterial.SetFloat("_FragmentHeight", fragmentHeight);
        waterMaterial.SetFloat("_NormalStrength", normalStrength);

        // Update material properties
        waterMaterial.SetColor("_FresnelColor", fresnelColor);
        waterMaterial.SetFloat("_FresnelPower", fresnelPower);
        waterMaterial.SetFloat("_Smoothness", smoothness);
        waterMaterial.SetFloat("_SpecularStrength", specularStrength);

        // Foam
        waterMaterial.SetColor("_TipColor", tipColor);
        waterMaterial.SetFloat("_TipThreshold", tipThreshold);
        waterMaterial.SetFloat("_TipSpread", tipSpread);

        // Underwater & refraction
        waterMaterial.SetColor("_ShallowColor", shallowColor);
        waterMaterial.SetColor("_DeepColor", deepColor);
        waterMaterial.SetFloat("_DepthDensity", depthDensity);
        waterMaterial.SetFloat("_RefractionStrength", refractionStrength);
    }

    void OnDisable() {
        if (waveBuffer != null) {
            waveBuffer.Release();
            waveBuffer = null;
        }

        if (waterMaterial != null) {
            DestroyImmediate(waterMaterial);
            waterMaterial = null;
        }

        if (mesh != null) {
            DestroyImmediate(mesh);
            mesh = null;
        }
    }
}
