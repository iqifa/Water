using System;
using UnityEngine;

[RequireComponent(typeof(MeshFilter), typeof(MeshRenderer))]
public class StylizedWater : MonoBehaviour {

    [Header("Mesh Settings")]
    public int planeSize = 10;
    [Range(8, 256)]
    public int resolution = 128;

    [Header("Wave Settings (UE 谱生成, 与 GerstnerWater 相同)")]
    [Range(1, 64)]
    public int waveCount = 8;
    public int seed = 42;
    [Range(0f, 1f)]
    public float randomness = 0.0f;
    [Range(0.1f, 30f)]
    public float minWavelength = 2.0f;
    [Range(0.5f, 100f)]
    public float maxWavelength = 8.0f;
    [Range(0.5f, 4f)]
    public float wavelengthFalloff = 2.0f;
    [Range(0.0001f, 0.1f)]
    public float minAmplitude = 0.015f;
    [Range(0f, 2f)]
    public float maxAmplitude = 0.107f;
    [Range(0.5f, 4f)]
    public float amplitudeFalloff = 2.0f;
    [Range(0f, 360f)]
    public float windAngleDeg = 0f;
    [Range(0f, 1440f)]
    public float directionAngularSpreadDeg = 1325f;
    [Range(0.05f, 1f)]
    public float largeWaveSteepness = 0.2f;
    [Range(0.05f, 1f)]
    public float smallWaveSteepness = 0.4f;
    [Range(0.25f, 4f)]
    public float steepnessFalloff = 1.0f;
    [Range(0.05f, 3f)]
    public float speedMultiplier = 0.5f;

    [Header("Color Bands (三色阶) - EVA LCL 配色")]
    public Color shallowColor = new Color(1.0f, 0.72f, 0.25f, 1f);   // 亮琥珀橙
    public Color midColor = new Color(0.92f, 0.45f, 0.12f, 1f);      // 橙
    public Color deepColor = new Color(0.45f, 0.16f, 0.05f, 1f);     // 暗棕橘
    [Range(0.001f, 0.5f)]
    public float bandSmoothness = 0.03f;
    [Range(0f, 2f)]
    public float shallowBandStart = 0.15f;
    [Range(0f, 5f)]
    public float deepBandStart = 0.8f;

    [Header("Shore Foam (岸线泡沫描边)")]
    public Color shoreFoamColor = new Color(1.0f, 0.85f, 0.6f, 1f);  // 奶橙白
    [Range(0f, 1f)]
    public float shoreFoamWidth = 0.25f;
    [Range(0f, 50f)]
    public float shoreFoamNoiseScale = 12f;
    [Range(0f, 2f)]
    public float shoreFoamSpeed = 0.5f;

    [Header("Tip Foam (浪尖白沫)")]
    public Color tipColor = new Color(1.0f, 0.85f, 0.6f, 1f);        // 奶橙白
    [Range(0f, 1f)]
    public float tipThreshold = 0.75f;
    [Range(0.01f, 1f)]
    public float tipSpread = 0.15f;
    [Range(0f, 50f)]
    public float tipNoiseScale = 8f;

    [Header("View Glow (视野反光)")]
    public Color viewGlowColor = new Color(1.0f, 0.8f, 0.5f, 1f);    // 暖金反光
    [Range(1f, 16f)]
    public float viewGlowPower = 6f;
    [Range(0f, 1f)]
    public float viewGlowStrength = 0.5f;

    [Header("Specular (高光与闪点)")]
    public Color specularColor = new Color(1.0f, 0.9f, 0.65f, 1f);   // 暖白高光
    [Range(8f, 256f)]
    public float specularSize = 64f;
    [Range(0f, 4f)]
    public float specularStrength = 1.8f;
    [Range(0f, 1f)]
    public float glitterStrength = 0.35f;

    [Range(0, 6)]
    public int debugMode = 0;

    [Header("Shader")]
    public Shader waterShader;

    // Private variables
    private Material waterMaterial;
    private Mesh mesh;
    private ComputeBuffer waveBuffer;
    private ComputeBuffer steepnessBuffer;
    private Vector4[] waves;
    private Vector2[] steepnesses;

    void OnEnable() {
        CreateWaterMesh();
        CreateMaterial();
        GenerateWaves();
    }

    void CreateWaterMesh() {
        mesh = new Mesh();
        mesh.name = "StylizedWater";

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
            waterShader = Shader.Find("Custom/StylizedWaterURP");
            if (waterShader == null) {
                Debug.LogError("❌ Custom/StylizedWaterURP not found! Please assign the shader manually in the Inspector.");
                return;
            }
        }

        waterMaterial = new Material(waterShader);
        GetComponent<MeshRenderer>().material = waterMaterial;
    }

    // --- 参数快照 ---
    private int lastWaveCount, lastSeed;
    private float lastRandomness;
    private float lastMinWavelength, lastMaxWavelength, lastWavelengthFalloff;
    private float lastMinAmplitude, lastMaxAmplitude, lastAmplitudeFalloff;
    private float lastWindAngle, lastDirectionSpread;
    private float lastLargeSteep, lastSmallSteep, lastSteepnessFalloff;

    bool NeedsRegenerate() {
        bool changed =
            waveCount != lastWaveCount ||
            seed != lastSeed ||
            !Mathf.Approximately(randomness, lastRandomness) ||
            !Mathf.Approximately(minWavelength, lastMinWavelength) ||
            !Mathf.Approximately(maxWavelength, lastMaxWavelength) ||
            !Mathf.Approximately(wavelengthFalloff, lastWavelengthFalloff) ||
            !Mathf.Approximately(minAmplitude, lastMinAmplitude) ||
            !Mathf.Approximately(maxAmplitude, lastMaxAmplitude) ||
            !Mathf.Approximately(amplitudeFalloff, lastAmplitudeFalloff) ||
            !Mathf.Approximately(windAngleDeg, lastWindAngle) ||
            !Mathf.Approximately(directionAngularSpreadDeg, lastDirectionSpread) ||
            !Mathf.Approximately(largeWaveSteepness, lastLargeSteep) ||
            !Mathf.Approximately(smallWaveSteepness, lastSmallSteep) ||
            !Mathf.Approximately(steepnessFalloff, lastSteepnessFalloff);

        if (changed) {
            lastWaveCount = waveCount;
            lastSeed = seed;
            lastRandomness = randomness;
            lastMinWavelength = minWavelength;
            lastMaxWavelength = maxWavelength;
            lastWavelengthFalloff = wavelengthFalloff;
            lastMinAmplitude = minAmplitude;
            lastMaxAmplitude = maxAmplitude;
            lastAmplitudeFalloff = amplitudeFalloff;
            lastWindAngle = windAngleDeg;
            lastDirectionSpread = directionAngularSpreadDeg;
            lastLargeSteep = largeWaveSteepness;
            lastSmallSteep = smallWaveSteepness;
            lastSteepnessFalloff = steepnessFalloff;
        }
        return changed;
    }

    // 与 GerstnerWater 相同的 UE 频谱生成 (波长梯度插值 + 方向大散开 + 大波缓小波尖)
    public void GenerateWaves() {
        if (waves == null || waves.Length != 64) {
            waves = new Vector4[64];
            steepnesses = new Vector2[64];
        }
        Array.Clear(waves, 0, waves.Length);

        var rand = new System.Random(seed);

        for (int i = 0; i < waveCount; i++) {
            float alpha = Mathf.Clamp(
                1f - (float)i / waveCount + randomness * (((float)rand.NextDouble() * 2f - 1f) / waveCount),
                0f, 1f);

            float dirDeg = windAngleDeg;
            if (i > 0) {
                dirDeg += ((float)rand.NextDouble() * 2f - 1f) * directionAngularSpreadDeg;
            }
            float rad = dirDeg * Mathf.Deg2Rad;

            float wavelength = Mathf.Lerp(minWavelength, maxWavelength, Mathf.Pow(alpha, wavelengthFalloff));
            float amplitude = Mathf.Max(Mathf.Lerp(minAmplitude, maxAmplitude, Mathf.Pow(alpha, amplitudeFalloff)), 0.0001f);
            float steepness = Mathf.Lerp(largeWaveSteepness, smallWaveSteepness, Mathf.Pow((float)i / waveCount, steepnessFalloff));

            waves[i] = new Vector4(Mathf.Cos(rad), Mathf.Sin(rad), wavelength, amplitude);
            steepnesses[i] = new Vector2(steepness, 0f);
        }

        UpdateWaveBuffer();
    }

    void UpdateWaveBuffer() {
        if (waveBuffer != null) {
            waveBuffer.Release();
        }
        waveBuffer = new ComputeBuffer(64, sizeof(float) * 4);
        waveBuffer.SetData(waves);

        if (steepnessBuffer != null) {
            steepnessBuffer.Release();
        }
        steepnessBuffer = new ComputeBuffer(64, sizeof(float) * 2);
        steepnessBuffer.SetData(steepnesses);

        if (waterMaterial != null) {
            waterMaterial.SetBuffer("_Waves", waveBuffer);
            waterMaterial.SetBuffer("_Steepnesses", steepnessBuffer);
        }
    }

    void Update() {
        if (waterMaterial == null) return;

        if (NeedsRegenerate()) {
            GenerateWaves();
        }

        if (Input.GetKeyDown(KeyCode.Alpha0)) waterMaterial.SetFloat("_DebugMode", 0);
        if (Input.GetKeyDown(KeyCode.Alpha1)) waterMaterial.SetFloat("_DebugMode", 1);
        if (Input.GetKeyDown(KeyCode.Alpha2)) waterMaterial.SetFloat("_DebugMode", 2);
        if (Input.GetKeyDown(KeyCode.Alpha3)) waterMaterial.SetFloat("_DebugMode", 3);
        if (Input.GetKeyDown(KeyCode.Alpha4)) waterMaterial.SetFloat("_DebugMode", 4);
        if (Input.GetKeyDown(KeyCode.Alpha5)) waterMaterial.SetFloat("_DebugMode", 5);
        if (Input.GetKeyDown(KeyCode.Alpha6)) waterMaterial.SetFloat("_DebugMode", 6);
        waterMaterial.SetFloat("_DebugMode", debugMode);

        waterMaterial.SetInt("_WaveCount", waveCount);
        waterMaterial.SetFloat("_SpeedMultiplier", speedMultiplier);

        // Gerstner 打结防护 (与 GerstnerWater 相同)
        float steepSum = 0f;
        for (int i = 0; i < waveCount; i++) steepSum += steepnesses[i].x;
        float steepScale = (steepSum > 0.85f) ? 0.85f / steepSum : 1f;
        waterMaterial.SetFloat("_SteepnessScale", steepScale);

        // Color bands
        waterMaterial.SetColor("_ShallowColor", shallowColor);
        waterMaterial.SetColor("_MidColor", midColor);
        waterMaterial.SetColor("_DeepColor", deepColor);
        waterMaterial.SetFloat("_BandSmoothness", bandSmoothness);
        waterMaterial.SetFloat("_ShallowBandStart", shallowBandStart);
        waterMaterial.SetFloat("_DeepBandStart", deepBandStart);

        // Shore foam
        waterMaterial.SetColor("_ShoreFoamColor", shoreFoamColor);
        waterMaterial.SetFloat("_ShoreFoamWidth", shoreFoamWidth);
        waterMaterial.SetFloat("_ShoreFoamNoiseScale", shoreFoamNoiseScale);
        waterMaterial.SetFloat("_ShoreFoamSpeed", shoreFoamSpeed);

        // Tip foam
        waterMaterial.SetColor("_TipColor", tipColor);
        waterMaterial.SetFloat("_TipThreshold", tipThreshold);
        waterMaterial.SetFloat("_TipSpread", tipSpread);
        waterMaterial.SetFloat("_TipNoiseScale", tipNoiseScale);

        // View glow
        waterMaterial.SetColor("_ViewGlowColor", viewGlowColor);
        waterMaterial.SetFloat("_ViewGlowPower", viewGlowPower);
        waterMaterial.SetFloat("_ViewGlowStrength", viewGlowStrength);

        // Specular
        waterMaterial.SetColor("_SpecularColor", specularColor);
        waterMaterial.SetFloat("_SpecularSize", specularSize);
        waterMaterial.SetFloat("_SpecularStrength", specularStrength);
        waterMaterial.SetFloat("_GlitterStrength", glitterStrength);
    }

    void OnDisable() {
        if (waveBuffer != null) {
            waveBuffer.Release();
            waveBuffer = null;
        }

        if (steepnessBuffer != null) {
            steepnessBuffer.Release();
            steepnessBuffer = null;
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
