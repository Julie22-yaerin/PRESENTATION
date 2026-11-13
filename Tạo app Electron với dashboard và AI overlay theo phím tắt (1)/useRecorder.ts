import { useCallback, useEffect, useRef, useState } from 'react'

export const SAMPLE_RATE = 16000
const FRAME_SIZE = 4096

export interface RecordingResult {
  wav: Uint8Array
  durationMs: number
  peak: number
  sampleRate: number
}

export type RecorderErrorCode = 'insecure-context' | 'denied' | 'no-device' | 'unsupported' | 'unknown'

export interface RecorderError {
  code: RecorderErrorCode
  message: string
}

function writeString(view: DataView, offset: number, value: string): void {
  for (let i = 0; i < value.length; i += 1) view.setUint8(offset + i, value.charCodeAt(i))
}

/** 16-bit mono PCM WAV: the one container every OpenAI-compatible endpoint accepts. */
export function encodeWav(samples: Float32Array, sampleRate: number): Uint8Array {
  const buffer = new ArrayBuffer(44 + samples.length * 2)
  const view = new DataView(buffer)
  writeString(view, 0, 'RIFF')
  view.setUint32(4, 36 + samples.length * 2, true)
  writeString(view, 8, 'WAVE')
  writeString(view, 12, 'fmt ')
  view.setUint32(16, 16, true)
  view.setUint16(20, 1, true)
  view.setUint16(22, 1, true)
  view.setUint32(24, sampleRate, true)
  view.setUint32(28, sampleRate * 2, true)
  view.setUint16(32, 2, true)
  view.setUint16(34, 16, true)
  writeString(view, 36, 'data')
  view.setUint32(40, samples.length * 2, true)

  let offset = 44
  for (let i = 0; i < samples.length; i += 1) {
    const clamped = Math.max(-1, Math.min(1, samples[i]))
    view.setInt16(offset, clamped < 0 ? clamped * 0x8000 : clamped * 0x7fff, true)
    offset += 2
  }
  return new Uint8Array(buffer)
}

interface RecorderApi {
  level: number
  elapsedMs: number
  active: boolean
  error: RecorderError | null
  start: (deviceId: string) => Promise<boolean>
  stop: () => RecordingResult | null
  cancel: () => void
  reportDevices: () => Promise<void>
}

/**
 * Records with a raw PCM tap so the app never needs ffmpeg or MediaRecorder codec
 * differences across platforms. The same samples drive the level meter.
 */
export function useRecorder(onLevel: (level: number, elapsedMs: number) => void): RecorderApi {
  const [level, setLevel] = useState(0)
  const [elapsedMs, setElapsed] = useState(0)
  const [active, setActive] = useState(false)
  const [error, setError] = useState<RecorderError | null>(null)

  const contextRef = useRef<AudioContext | null>(null)
  const streamRef = useRef<MediaStream | null>(null)
  const nodeRef = useRef<ScriptProcessorNode | null>(null)
  const sinkRef = useRef<GainNode | null>(null)
  const chunksRef = useRef<Float32Array[]>([])
  const peakRef = useRef(0)
  const startedRef = useRef(0)
  const levelTimerRef = useRef<number | null>(null)

  const teardown = useCallback((): void => {
    if (levelTimerRef.current !== null) {
      window.clearInterval(levelTimerRef.current)
      levelTimerRef.current = null
    }
    const node = nodeRef.current
    if (node) {
      node.onaudioprocess = null
      try {
        node.disconnect()
      } catch {
        /* already detached */
      }
    }
    try {
      sinkRef.current?.disconnect()
    } catch {
      /* already detached */
    }
    streamRef.current?.getTracks().forEach((track) => track.stop())
    const context = contextRef.current
    if (context && context.state !== 'closed') void context.close()
    nodeRef.current = null
    sinkRef.current = null
    streamRef.current = null
    contextRef.current = null
    chunksRef.current = []
  }, [])

  useEffect(() => teardown, [teardown])

  const reportDevices = useCallback(async (): Promise<void> => {
    if (!navigator.mediaDevices?.enumerateDevices) return
    try {
      const devices = await navigator.mediaDevices.enumerateDevices()
      const mics = devices.filter((device) => device.kind === 'audioinput')
      window.bubble.reportMic({
        devices: mics.length,
        labels: mics.map((device) => device.label).filter(Boolean),
        permission: mics.some((device) => device.label) ? 'granted' : 'prompt',
        at: Date.now()
      })
    } catch {
      /* enumeration is best effort */
    }
  }, [])

  const start = useCallback(
    async (deviceId: string): Promise<boolean> => {
      if (!window.isSecureContext) {
        setError({ code: 'insecure-context', message: 'Frontend không ở ngữ cảnh an toàn nên không dùng được mic.' })
        return false
      }
      if (!navigator.mediaDevices?.getUserMedia) {
        setError({ code: 'unsupported', message: 'Electron build này không có getUserMedia.' })
        return false
      }

      teardown()
      setError(null)
      const audio: MediaTrackConstraints = {
        channelCount: 1,
        echoCancellation: true,
        noiseSuppression: true,
        autoGainControl: true
      }
      if (deviceId && deviceId !== 'default') audio.deviceId = { exact: deviceId }

      try {
        const stream = await navigator.mediaDevices.getUserMedia({ audio, video: false })
        streamRef.current = stream
        const context = new AudioContext({ sampleRate: SAMPLE_RATE })
        contextRef.current = context
        if (context.state === 'suspended') await context.resume()

        const source = context.createMediaStreamSource(stream)
        const node = context.createScriptProcessor(FRAME_SIZE, 1, 1)
        nodeRef.current = node
        // A silent sink keeps the processing chain alive without feeding audio to speakers.
        const sink = context.createGain()
        sink.gain.value = 0
        sinkRef.current = sink

        node.onaudioprocess = (event) => {
          const input = event.inputBuffer.getChannelData(0)
          chunksRef.current.push(new Float32Array(input))
          let peak = peakRef.current
          for (let i = 0; i < input.length; i += 1) {
            const magnitude = Math.abs(input[i])
            if (magnitude > peak) peak = magnitude
          }
          peakRef.current = peak
        }

        source.connect(node)
        node.connect(sink)
        sink.connect(context.destination)

        chunksRef.current = []
        peakRef.current = 0
        startedRef.current = Date.now()
        setActive(true)
        void reportDevices()

        levelTimerRef.current = window.setInterval(() => {
          const elapsed = Date.now() - startedRef.current
          // Peak per interval approximates the voice meter without a second analyser node.
          let instant = 0
          const last = chunksRef.current[chunksRef.current.length - 1]
          if (last) {
            let sum = 0
            for (let i = 0; i < last.length; i += 1) sum += last[i] * last[i]
            instant = Math.min(1, Math.sqrt(sum / last.length) * 4)
          }
          setLevel(instant)
          setElapsed(elapsed)
          onLevel(instant, elapsed)
        }, 90)

        return true
      } catch (caught) {
        const name = caught instanceof DOMException ? caught.name : ''
        const message = caught instanceof Error ? caught.message : String(caught)
        const code: RecorderErrorCode =
          name === 'NotAllowedError' || name === 'SecurityError'
            ? 'denied'
            : name === 'NotFoundError' || name === 'OverconstrainedError'
              ? 'no-device'
              : 'unknown'
        const hint =
          code === 'denied'
            ? 'Mic bị từ chối. Cấp quyền trong System Settings → Privacy & Security → Microphone rồi bấm lại.'
            : code === 'no-device'
              ? 'Không tìm thấy thiết bị ghi âm nào, hoặc thiết bị đã chọn không còn tồn tại.'
              : `Không bật được mic: ${message}`
        setError({ code, message: hint })
        window.bubble.reportRecordError(hint)
        window.bubble.reportMic({ devices: 0, labels: [], permission: code === 'denied' ? 'denied' : 'unknown', at: Date.now() })
        teardown()
        setActive(false)
        return false
      }
    },
    [onLevel, reportDevices, teardown]
  )

  const stop = useCallback((): RecordingResult | null => {
    if (!contextRef.current) return null
    const chunks = chunksRef.current
    const total = chunks.reduce((sum, chunk) => sum + chunk.length, 0)
    const durationMs = startedRef.current ? Date.now() - startedRef.current : 0
    const pcm = new Float32Array(total)
    let cursor = 0
    for (const chunk of chunks) {
      pcm.set(chunk, cursor)
      cursor += chunk.length
    }
    const result: RecordingResult = {
      wav: encodeWav(pcm, SAMPLE_RATE),
      durationMs,
      peak: peakRef.current,
      sampleRate: SAMPLE_RATE
    }
    teardown()
    setActive(false)
    setLevel(0)
    return result
  }, [teardown])

  const cancel = useCallback((): void => {
    teardown()
    setActive(false)
    setLevel(0)
  }, [teardown])

  return { level, elapsedMs, active, error, start, stop, cancel, reportDevices }
}
