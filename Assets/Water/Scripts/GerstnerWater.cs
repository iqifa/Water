using System;
using UnityEngine;

[RequireComponent(typeof(MeshFilter), typeof(MeshRenderer))]
public class GerstnerWater : MonoBehaviour {

    [Header("Mesh Settings")]
    public int planeSize = 10;
    // Gerstner 波对网格密度敏感: 分辨率不足短波会混叠成雪花噪声
    // 经验: 最短波长至少要跨 6~8 个格子 (planeSize/resolution * 8 <= minWavelength)
    [Range(8, 256)]
    public int resolution = 128;

    [Header("Wave Settings (UE 谱生成算法)")]
    [Range(1, 64)]
    public int waveCount = 16;
    public int seed = 42;
    [Range(0f, 1f)]
    public float randomness = 0.0f;

    [Header("Wave Spectrum (频谱, UE 默认值 cm→m 等比换算)")]
    // UE 默认: 波长 521~6000cm, 振幅 4~80cm, 12/20 倍谱宽.
    // 大谱宽是 UE 观感的关键: 60m 大涌浪主导整体起伏, 小波只添细节.
    // 注意: minWavelength 不要低于 planeSize/resolution*8, 否则网格采不出来 (混叠成噪点)
    [Range(0.1f, 100f)]
    public float minWavelength = 5.21f;
    [Range(0.5f, 200f)]
    public float maxWavelength = 60.0f;
    [Range(0.5f, 4f)]
    public float wavelengthFalloff = 2.0f;
    [Range(0.0001f, 0.1f)]
    public float minAmplitude = 0.04f;
    [Range(0f, 2f)]
    public float maxAmplitude = 0.8f;
    [Range(0.5f, 4f)]
    public float amplitudeFalloff = 2.0f;

    [Header("Direction & Steepness")]
    [Range(0f, 360f)]
    public float windAngleDeg = 0f;
    // UE 默认 1325° (超过一圈 = 方向完全均匀随机, 各方向浪涌交叉)
    [Range(0f, 1440f)]
    public float directionAngularSpreadDeg = 1325f;
    [Range(0.05f, 1f)]
    public float largeWaveSteepness = 0.2f;
    [Range(0.05f, 1f)]
    public float smallWaveSteepness = 0.4f;
    [Range(0.25f, 4f)]
    public float steepnessFalloff = 1.0f;
    // 波速系数: 1 = UE 原始物理 (ω=√(kg), 波长振幅已等比 cm→m, 时间行为与 UE 完全一致, 无需缩放)
    // 之前 0.1 是配合 2~8m 窄谱伪造"原地涌动"的补丁, 换真谱后不再需要
    [Range(0.05f, 3f)]
    public float speedMultiplier = 1.0f;
    // 水平摆动增幅: 放大 Gerstner 水平位移. 1 = UE 标准 Gerstner (质点圆轨迹)
    // >1 会破坏几何一致性 (水平/垂直不同步), 仅作风格化选项
    [Range(0f, 4f)]
    public float horizontalBoost = 1.0f;
    // Gerstner 打结防护: 折叠发生在方向张量 Σ Sᵢ·DᵢDᵢᵀ 最大特征值 >1 的方向上,
    // 把它钳到该值 (≈0.85 保留浪尖利落, 0 = 不钳制/UE 原版).
    // 只统计动顶点的 [0, middleFrequencyMaxIndex] 波段 — 像素法线段不移动几何
    [Range(0f, 2f)]
    public float steepnessClamp = 0.85f;

    [Header("Wave Frequency Bands (频率分档, UE GetPerFrequencyGerstnerWaves)")]
    // 波按索引排序(0=最长): [0,low] 动顶点形成大涌浪; (low,mid] 动顶点形成中浪; (mid,N] 只在像素算法线
    [Range(1, 64)]
    public int lowFrequencyMaxIndex = 4;
    [Range(1, 64)]
    public int middleFrequencyMaxIndex = 10;

    [Header("Material Settings")]
    public Color fresnelColor = new Color(0.7f, 0.85f, 0.95f, 1f);
    [Range(0.005f, 0.2f)]
    public float fresnelBase = 0.02f;
    // 菲涅尔专用平滑法线强度: 0=只看大形状, 1=跟细节法线 (参考项目同款)
    [Range(0f, 1f)]
    public float fresnelNormalStrength = 0.2f;
    [Range(0f, 1f)]
    public float smoothness = 0.95f;
    [Range(0f, 5f)]
    public float specularStrength = 1.0f;
    [Range(0f, 2f)]
    public float normalStrength = 1.0f;

    [Header("Foam Settings (浪尖白沫)")]
    public Color tipColor = new Color(1f, 1f, 1f, 1f);
    // 归一化浪高阈值: 0.9 = 只有最高的波峰出沫 (调低会白沫糊满水面)
    [Range(-1f, 1f)]
    public float tipThreshold = 0.9f;
    [Range(0.01f, 1f)]
    public float tipSpread = 0.08f;

    [Header("Underwater Settings (水体光学, Beer-Lambert)")]
    // 透射 tint: 1 米穿水后的剩余比例. 白=清水; 淡蓝=水吸收红绿光.
    // 物体光按 exp(-tint^depth) 衰减, 近处几乎不染色 (不是"有色玻璃")
    public Color shallowColor = new Color(0.8f, 0.92f, 0.95f, 1f);
    // 内散射色: 水体自色, 随深度累积. 无物体(无限深)处透射全灭, 只剩这个色
    public Color deepColor = new Color(0.05f, 0.2f, 0.3f, 1f);
    // 吸收/散射率 (1/米): 越大越浑浊. 岸浅处透亮, 深处饱和成 scatter 色
    [Range(0.005f, 2.0f)]
    public float depthDensity = 0.15f;
    [Range(0f, 0.2f)]
    public float refractionStrength = 0.02f;

    [Header("Feature Toggles (功能开关, 对应 shader 分块)")]
    public bool vertexDisplaceOn = true;     // [波] 顶点位移
    public bool shoreAttenOn = true;         // [波] 岸边浪衰减
    public bool refractionOn = true;         // [折射] 屏幕空间折射
    public bool scatterOn = true;            // [散射] 水体散射/吸收
    public bool fresnelOn = true;            // [菲涅尔]
    public bool specularOn = true;           // [高光]
    public bool tipFoamOn = true;            // [泡沫] 浪尖白沫
    public bool shoreFoamOn = true;          // [泡沫] 岸边/物体边缘浮沫
    public bool ssrOn = true;                // [反射] SSR
    public bool planarOn = true;             // [反射] 平面镜面反射

    [Header("Shader")]
    public Shader waterShader;

    // 调试: 按 0-6 切换调试视图 (0=正常 1=法线 2=菲涅尔 3=白沫 4=浪高 5=水下色 6=高光)
    [Range(0, 6)]
    public int debugMode = 0;

    // Private variables
    private Material waterMaterial;
    private Mesh mesh;
    private ComputeBuffer waveBuffer;
    private ComputeBuffer steepnessBuffer;
    // 每波数据: x=dir.x, y=dir.z, z=波长, w=振幅; 第二个数组 x=陡峭度, y=初相位(UE 恒为 0)
    private Vector4[] waves;
    private Vector2[] steepnesses;

    void OnEnable() {
        CreateWaterMesh();
        CreateMaterial();
        GenerateWaves();
    }

    void CreateWaterMesh() {
        mesh = new Mesh();
        mesh.name = "GerstnerWater";

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
            waterShader = Shader.Find("Custom/GerstnerWaterURP");
            if (waterShader == null) {
                Debug.LogError("❌ Custom/GerstnerWaterURP not found! Please assign the shader manually in the Inspector.");
                return;
            }
            Debug.Log("✓ Found URP Shader: Custom/GerstnerWaterURP");
        }

        waterMaterial = new Material(waterShader);
        GetComponent<MeshRenderer>().material = waterMaterial;
        Debug.Log($"🌊 Gerstner water material created with shader: {waterShader.name}");
    }

    // --- 参数快照: 检测 Inspector 改动, 变了才重新生成波 ---
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

    // 照 UE GerstnerWaterWaves.cpp / UGerstnerWaterWaveGeneratorSimple::GenerateGerstnerWaves 逐行移植:
    //   Alpha_i = clamp(1 - i/N + Randomness*rand(±1/N))
    //   波长   = Lerp(Min, Max, Alpha^WavelengthFalloff)   第0波最长, 按序递减
    //   振幅   = Lerp(Min, Max, Alpha^AmplitudeFalloff)    大波配大振幅
    //   陡峭度 = Lerp(Large, Small, (i/N)^SteepnessFalloff) 大波缓, 小波尖
    //   方向   = 风向 ± Spread 随机 (第0波不偏转)
    public void GenerateWaves() {
        if (waves == null || waves.Length != 64) {
            waves = new Vector4[64];
            steepnesses = new Vector2[64];
        }
        // 未使用的波槽位清零 (振幅=0, 不产生位移, 避免 NaN)
        Array.Clear(waves, 0, waves.Length);

        var rand = new System.Random(seed);

        for (int i = 0; i < waveCount; i++) {
            // UE: Alpha = Clamp(1 - i/N + Randomness * FRandRange(-1/N, 1/N), 0, 1)
            float alpha = Mathf.Clamp(
                1f - (float)i / waveCount + randomness * (((float)rand.NextDouble() * 2f - 1f) / waveCount),
                0f, 1f);

            // 方向: 风向为基, 第0波不偏转, 其余随机偏转 ±Spread (UE 同款)
            float dirDeg = windAngleDeg;
            if (i > 0) {
                dirDeg += ((float)rand.NextDouble() * 2f - 1f) * directionAngularSpreadDeg;
            }
            float rad = dirDeg * Mathf.Deg2Rad;

            float wavelength = Mathf.Lerp(minWavelength, maxWavelength, Mathf.Pow(alpha, wavelengthFalloff));
            float amplitude = Mathf.Max(Mathf.Lerp(minAmplitude, maxAmplitude, Mathf.Pow(alpha, amplitudeFalloff)), 0.0001f);
            float steepness = Mathf.Lerp(largeWaveSteepness, smallWaveSteepness, Mathf.Pow((float)i / waveCount, steepnessFalloff));

            waves[i] = new Vector4(Mathf.Cos(rad), Mathf.Sin(rad), wavelength, amplitude);
            steepnesses[i] = new Vector2(steepness, 0f); // UE 无随机初相位
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
        // 每波: x=陡峭度, y=初相位
        steepnessBuffer = new ComputeBuffer(64, sizeof(float) * 2);
        steepnessBuffer.SetData(steepnesses);

        if (waterMaterial != null) {
            waterMaterial.SetBuffer("_Waves", waveBuffer);
            waterMaterial.SetBuffer("_Steepnesses", steepnessBuffer);
        }
    }

    void Update() {
        if (waterMaterial == null) return;

        // 调试: 按 0-6 切换调试视图 (0=正常 1=法线 2=菲涅尔 3=白沫 4=浪高 5=水下色 6=高光)
        if (Input.GetKeyDown(KeyCode.Alpha0)) waterMaterial.SetFloat("_DebugMode", 0);
        if (Input.GetKeyDown(KeyCode.Alpha1)) waterMaterial.SetFloat("_DebugMode", 1);
        if (Input.GetKeyDown(KeyCode.Alpha2)) waterMaterial.SetFloat("_DebugMode", 2);
        if (Input.GetKeyDown(KeyCode.Alpha3)) waterMaterial.SetFloat("_DebugMode", 3);
        if (Input.GetKeyDown(KeyCode.Alpha4)) waterMaterial.SetFloat("_DebugMode", 4);
        if (Input.GetKeyDown(KeyCode.Alpha5)) waterMaterial.SetFloat("_DebugMode", 5);
        if (Input.GetKeyDown(KeyCode.Alpha6)) waterMaterial.SetFloat("_DebugMode", 6);

        // 参数变化时重新生成波 (可复现, 由 seed 控制)
        if (NeedsRegenerate()) {
            GenerateWaves();
        }

        waterMaterial.SetInt("_WaveCount", waveCount);
        waterMaterial.SetInt("_LowFrequencyMaxIndex", lowFrequencyMaxIndex);
        waterMaterial.SetInt("_MiddleFrequencyMaxIndex", middleFrequencyMaxIndex);
        waterMaterial.SetFloat("_SpeedMultiplier", speedMultiplier);
        waterMaterial.SetFloat("_HorizontalBoost", horizontalBoost);
        waterMaterial.SetFloat("_DebugMode", debugMode);

        // Gerstner 打结防护 (对照截图里的洋红斑 = 波峰卷折法线翻转):
        // 折叠条件是方向张量 Σ Sᵢ·DᵢDᵢᵀ 在某方向 d 上超过 1 (即 Σ Sᵢ·(d·Dᵢ)² > 1),
        // 其最大特征值为 λ = (Sxx+Szz)/2 + sqrt(((Sxx-Szz)/2)² + Sxz²).
        // 只对动顶点的 [0, middleIndex] 波段钳制; 全向 spread 下各波水平位移互相抵消,
        // 该判据不会像朴素 ΣS 求和那样误伤 — 方向错开的波不被压陡峭度.
        int lastDisplaced = Mathf.Min(middleFrequencyMaxIndex + 1, waveCount);
        float sxx = 0f, szz = 0f, sxz = 0f;
        for (int i = 0; i < lastDisplaced; i++) {
            float dx = waves[i].x, dz = waves[i].y;
            float s = steepnesses[i].x;
            sxx += s * dx * dx;
            szz += s * dz * dz;
            sxz += s * dx * dz;
        }
        float mean = (sxx + szz) * 0.5f;
        float lambdaMax = mean + Mathf.Sqrt((sxx - mean) * (sxx - mean) + sxz * sxz);
        float steepScale = (steepnessClamp > 0f && lambdaMax > steepnessClamp)
            ? steepnessClamp / lambdaMax : 1f;
        waterMaterial.SetFloat("_SteepnessScale", steepScale);

        // Material
        waterMaterial.SetColor("_FresnelColor", fresnelColor);
        waterMaterial.SetFloat("_FresnelBase", fresnelBase);
        waterMaterial.SetFloat("_FresnelNormalStrength", fresnelNormalStrength);
        waterMaterial.SetFloat("_Smoothness", smoothness);
        waterMaterial.SetFloat("_SpecularStrength", specularStrength);
        waterMaterial.SetFloat("_NormalStrength", normalStrength);

        // Foam
        waterMaterial.SetColor("_TipColor", tipColor);
        waterMaterial.SetFloat("_TipThreshold", tipThreshold);
        waterMaterial.SetFloat("_TipSpread", tipSpread);

        // Underwater & refraction
        waterMaterial.SetColor("_ShallowColor", shallowColor);
        waterMaterial.SetColor("_DeepColor", deepColor);
        waterMaterial.SetFloat("_DepthDensity", depthDensity);
        waterMaterial.SetFloat("_RefractionStrength", refractionStrength);

        // Feature toggles (shader 分块开关)
        waterMaterial.SetFloat("_VertexDisplaceOn", vertexDisplaceOn ? 1f : 0f);
        waterMaterial.SetFloat("_ShoreAttenOn", shoreAttenOn ? 1f : 0f);
        waterMaterial.SetFloat("_RefractionOn", refractionOn ? 1f : 0f);
        waterMaterial.SetFloat("_ScatterOn", scatterOn ? 1f : 0f);
        waterMaterial.SetFloat("_FresnelOn", fresnelOn ? 1f : 0f);
        waterMaterial.SetFloat("_SpecularOn", specularOn ? 1f : 0f);
        waterMaterial.SetFloat("_TipFoamOn", tipFoamOn ? 1f : 0f);
        waterMaterial.SetFloat("_ShoreFoamOn", shoreFoamOn ? 1f : 0f);
        waterMaterial.SetFloat("_SSROn", ssrOn ? 1f : 0f);
        waterMaterial.SetFloat("_PlanarOn", planarOn ? 1f : 0f);
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
