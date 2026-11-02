using System;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

/// <summary>
/// URP 平面镜面反射: 用镜像相机把水面之上的场景渲到 RT,
/// 供 GerstnerWaterURP 采样 (_ReflectionTex + _ReflectionUVMatrix + _ReflectionPlaneHeight).
/// 挂在水面物体上. 方案参考 Unity Boat Attack 示例的 PlanarReflections.
/// </summary>
[ExecuteAlways]
[RequireComponent(typeof(Renderer))]
public class WaterPlanarReflection : MonoBehaviour
{
    [Header("Reflection (镜面反射)")]
    [Range(256, 2048)]
    public int textureSize = 1024;         // 反射图分辨率: 256 会满屏马赛克, 1024 起步细腻
    [Range(0f, 1f)]
    public float clipPlaneOffset = 0.05f;  // 裁剪面上移 (略高于水面, 滤掉紧贴水面的浪尖残影)
    public LayerMask reflectionLayers = ~0;
    [Range(0f, 1f)]
    public float reflectionStrength = 0.85f;

    private Camera reflectionCamera;
    private RenderTexture reflectionRT;

    private static readonly int ReflectionTexID = Shader.PropertyToID("_ReflectionTex");
    private static readonly int ReflectionUVMatrixID = Shader.PropertyToID("_ReflectionUVMatrix");
    private static readonly int ReflectionPlaneHeightID = Shader.PropertyToID("_ReflectionPlaneHeight");
    private static readonly int ReflectionStrengthID = Shader.PropertyToID("_ReflectionStrength");

    void OnEnable()
    {
        CreateReflectionObjects();
        RenderPipelineManager.beginCameraRendering += OnBeginCameraRendering;
    }

    void OnDisable()
    {
        RenderPipelineManager.beginCameraRendering -= OnBeginCameraRendering;
        Cleanup();
    }

    void CreateReflectionObjects()
    {
        if (reflectionRT == null)
        {
            reflectionRT = new RenderTexture(textureSize, textureSize, 16, RenderTextureFormat.ARGBHalf)
            {
                name = "WaterReflectionRT"
            };
        }

        if (reflectionCamera == null)
        {
            var go = new GameObject("WaterReflectionCam") { hideFlags = HideFlags.DontSave };
            reflectionCamera = go.AddComponent<Camera>();
            reflectionCamera.enabled = false;
            reflectionCamera.targetTexture = reflectionRT;
            reflectionCamera.allowMSAA = false;
            reflectionCamera.useOcclusionCulling = false;
        }
    }

    void Cleanup()
    {
        if (reflectionCamera != null)
        {
            DestroyImmediate(reflectionCamera.gameObject);
            reflectionCamera = null;
        }
        if (reflectionRT != null)
        {
            reflectionRT.Release();
            DestroyImmediate(reflectionRT);
            reflectionRT = null;
        }
    }

    void OnBeginCameraRendering(ScriptableRenderContext context, Camera camera)
    {
        // 跳过反射相机自身 / 非游戏&场景相机 (预览窗等)
        if (camera == reflectionCamera) return;
        if (camera.cameraType != CameraType.Game && camera.cameraType != CameraType.SceneView) return;

        float planeY = transform.position.y;
        Vector3 camPos = camera.transform.position;
        if (camPos.y < planeY) return; // 相机在水面下: 不渲反射

        CreateReflectionObjects();
        if (TryGetComponent<Renderer>(out var r) && r.sharedMaterial != null)
        {
            r.sharedMaterial.SetFloat(ReflectionStrengthID, reflectionStrength);
            r.sharedMaterial.SetFloat(ReflectionPlaneHeightID, planeY);
            // 关键: 把反射 RT 绑到材质 (GerstnerWater 每次 OnEnable 重建材质,
            // 属性回落到默认 "black", 不绑就永远采到黑 => 反射不可见)
            r.sharedMaterial.SetTexture(ReflectionTexID, reflectionRT);
        }

        // ---- 镜像相机姿态 (关于 y = planeY 平面) ----
        Vector3 mirroredPos = new Vector3(camPos.x, 2f * planeY - camPos.y, camPos.z);
        Vector3 mirroredForward = Vector3.Reflect(camera.transform.forward, Vector3.up);
        Vector3 mirroredUp = Vector3.Reflect(camera.transform.up, Vector3.up);
        reflectionCamera.transform.SetPositionAndRotation(mirroredPos, Quaternion.LookRotation(mirroredForward, mirroredUp));
        reflectionCamera.fieldOfView = camera.fieldOfView;
        reflectionCamera.aspect = camera.aspect;
        reflectionCamera.nearClipPlane = camera.nearClipPlane;
        reflectionCamera.farClipPlane = camera.farClipPlane;
        reflectionCamera.cullingMask = reflectionLayers;

        // 斜截视锥体: 近裁剪面 = 水面, 反射里看不到水下几何.
        // 用 Camera.CalculateObliqueMatrix (Boat Attack 同款), 不要手搓推导
        Vector4 clipPlane = CameraSpacePlane(planeY);
        Matrix4x4 proj = reflectionCamera.CalculateObliqueMatrix(clipPlane);
        reflectionCamera.projectionMatrix = proj;
        // 裁剪与渲染用同一视锥体
        reflectionCamera.cullingMatrix = proj * reflectionCamera.worldToCameraMatrix;

        // ---- 渲染 (镜像绕序反转) ----
        GL.invertCulling = true;
#pragma warning disable CS0618 // URP14 中 RenderSingleCamera 标记过时但仍可用 (Boat Attack 同款)
        UniversalRenderPipeline.RenderSingleCamera(context, reflectionCamera);
#pragma warning restore CS0618
        GL.invertCulling = false;

        // ---- UV 矩阵: 世界点 -> 反射纹理 UV ----
        if (TryGetComponent<Renderer>(out var renderer) && renderer.sharedMaterial != null)
        {
            Matrix4x4 worldToTex =
                Matrix4x4.Translate(new Vector3(0.5f, 0.5f, 0.5f))
                * Matrix4x4.Scale(new Vector3(0.5f, 0.5f, 0.5f))
                * reflectionCamera.projectionMatrix
                * reflectionCamera.worldToCameraMatrix;
            renderer.sharedMaterial.SetMatrix(ReflectionUVMatrixID, worldToTex);
        }
    }

    // 水面平面在反射相机相机空间中的表示.
    // CalculateObliqueMatrix 要求: 平面用相机空间表示, 法线朝向相机可见的一侧,
    // 形式 dot(n, p) + d = 0, 保留 dot(n,p)+d > 0 的半空间.
    // 反射相机在水下往上渲, 相机可见的是水面之上的内容 => 法线取世界向下 (-up).
    private Vector4 CameraSpacePlane(float planeY)
    {
        Vector3 planePos = new Vector3(0f, planeY + clipPlaneOffset, 0f);
        // 反射相机在水下往上渲, 要保留水面之上的内容 => 平面朝下 (-up) 才面向相机
        Vector3 normal = -Vector3.up;
        Matrix4x4 w2c = reflectionCamera.worldToCameraMatrix;
        Vector3 posInCam = w2c.MultiplyPoint(planePos);
        Vector3 normalInCam = w2c.MultiplyVector(normal);
        float dist = -Vector3.Dot(posInCam, normalInCam);
        return new Vector4(normalInCam.x, normalInCam.y, normalInCam.z, dist);
    }
}
