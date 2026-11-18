using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

public class GF2_CharacterMRT_Feature : ScriptableRendererFeature
{
    [System.Serializable]
    public class Settings
    {
        public LayerMask characterLayer = ~0; // 在 Inspector 里选为 Character 层
    }

    public Settings settings = new Settings();

    class CharacterMRTPass : ScriptableRenderPass
    {
        private RTHandle m_NormalFlagRT;
        private readonly RenderTargetIdentifier[] m_MRT = new RenderTargetIdentifier[2];
        private static readonly int s_NormalFlagRT_ID = Shader.PropertyToID("_GF2_NormalFlagRT");

        private FilteringSettings m_FilteringSettings;
        private readonly List<ShaderTagId> m_ShaderTagIds = new List<ShaderTagId>
        {
            new ShaderTagId("GF2ForwardMRT"),
            new ShaderTagId("GF2OutlineMRT")
        };

        public CharacterMRTPass(LayerMask layerMask)
        {
            // 在不透明场景画完后、透明物体前绘制角色双 MRT
            renderPassEvent = RenderPassEvent.AfterRenderingOpaques;
            m_FilteringSettings = new FilteringSettings(RenderQueueRange.opaque, layerMask);
        }

        public override void OnCameraSetup(CommandBuffer cmd, ref RenderingData renderingData)
        {
            var desc = renderingData.cameraData.cameraTargetDescriptor;
            desc.graphicsFormat = UnityEngine.Experimental.Rendering.GraphicsFormat.R8G8B8A8_UNorm;
            desc.depthBufferBits = 0; // 深度复用相机的 DepthBuffer
            desc.msaaSamples = 1;

            RenderingUtils.ReAllocateIfNeeded(ref m_NormalFlagRT, desc, FilterMode.Point, TextureWrapMode.Clamp, name: "_GF2_NormalFlagRT");
        }

        public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
        {
            CommandBuffer cmd = CommandBufferPool.Get("GF2 Character Dual MRT");

            // 1. 先单独清一次 RT1（默认 B=0.0 表示普通背景，允许吃全屏 AO）
            cmd.SetRenderTarget(m_NormalFlagRT);
            cmd.ClearRenderTarget(false, true, new Color(0.5f, 0.5f, 0.0f, 0.5f));

            // 2. 绑定双 MRT（RT0 = 相机 HDR 颜色，RT1 = 法线与角色标记）+ 相机深度
            m_MRT[0] = renderingData.cameraData.renderer.cameraColorTargetHandle;
            m_MRT[1] = m_NormalFlagRT;
            cmd.SetRenderTarget(m_MRT, renderingData.cameraData.renderer.cameraDepthTargetHandle);

            // 暴露给后续 GTAO / Bloom 后处理读取
            cmd.SetGlobalTexture(s_NormalFlagRT_ID, m_NormalFlagRT);
            context.ExecuteCommandBuffer(cmd);
            CommandBufferPool.Release(cmd);

            // 3. 正式提交绘制角色（此时双 MRT 处于激活状态，SV_Target0 和 SV_Target1 都会正常写入）
            var drawingSettings = CreateDrawingSettings(m_ShaderTagIds, ref renderingData, SortingCriteria.CommonOpaque);
            context.DrawRenderers(renderingData.cullResults, ref drawingSettings, ref m_FilteringSettings);
        }

        public void Dispose()
        {
            m_NormalFlagRT?.Release();
        }
    }

    private CharacterMRTPass m_Pass;

    public override void Create()
    {
        m_Pass = new CharacterMRTPass(settings.characterLayer);
    }

    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
    {
        renderer.EnqueuePass(m_Pass);
    }

    protected override void Dispose(bool disposing)
    {
        m_Pass?.Dispose();
    }
}