import { useEffect, useMemo, useState } from 'react'
import { useApp } from '../context'
import { Badge, Button, Card, Field, NumberInput, Segmented, Select, TextArea, TextInput, Toggle } from '../components'
import { HOTKEY_KEYS, type AppSettings } from '../../../../shared/types'
import type { AudioDeviceInfo } from '../../../../shared/bridge'
import { guessKeyName } from '../../lib/format'

export function Settings() {
  const { bundle, models, actions, busy, notify, learning } = useApp()
  const saved = bundle?.settings ?? null
  const runtime = bundle?.runtime ?? null
  const [draft, setDraft] = useState<AppSettings | null>(saved)
  const [keyValue, setKeyValue] = useState('')
  const [devices, setDevices] = useState<AudioDeviceInfo[]>([])
  const [lastTest, setLastTest] = useState<string | null>(null)

  useEffect(() => {
    setDraft(saved)
  }, [saved])

  useEffect(() => {
    void window.bubble.audioDevices().then(setDevices)
  }, [busy])

  const dirty = useMemo(() => JSON.stringify(draft) !== JSON.stringify(saved), [draft, saved])

  if (!draft || !runtime) return <Card title="Đang tải cấu hình…"><p className="muted">Vui lòng đợi.</p></Card>

  const patchSection = <K extends keyof AppSettings>(section: K, value: Partial<AppSettings[K]>): void => {
    setDraft((current) => (current ? { ...current, [section]: { ...current[section], ...value } } : current))
  }

  const save = async (): Promise<void> => {
    await actions.save(draft)
    notify('Đã lưu cài đặt', 'ok')
  }

  return (
    <div className="settings">
      <div className="settings-head">
        <p className="settings-note">
          Thay đổi chỉ áp dụng khi bấm <strong>Lưu</strong>. API key không nằm trong tệp cấu hình mà được mã hoá theo tài khoản
          hệ điều hành.
        </p>
        <div className="row-gap">
          {dirty ? <Badge tone="warn">Chưa lưu</Badge> : null}
          <Button onClick={() => setDraft(saved)} disabled={!dirty}>
            Hoàn tác
          </Button>
          <Button variant="primary" onClick={() => void save()} disabled={!dirty || busy === 'save'}>
            {busy === 'save' ? 'Đang lưu…' : 'Lưu thay đổi'}
          </Button>
        </div>
      </div>

      <Card
        title="AI"
        subtitle="Endpoint tương thích OpenAI: chat completions + audio transcriptions"
        actions={
          <div className="row-gap">
            <Button onClick={() => void actions.loadModels()} disabled={busy === 'models'}>
              {busy === 'models' ? 'Đang tải…' : 'Tải danh sách model'}
            </Button>
            <Button
              onClick={async () => {
                const result = await window.bubble.testConnection()
                setLastTest(result.ok ? `OK · ${result.latencyMs}ms · ${result.detail}` : `Lỗi · ${result.detail}`)
              }}
              disabled={busy === 'test'}
            >
              Kiểm tra kết nối
            </Button>
          </div>
        }
      >
        <div className="grid-2">
          <Field label="Base URL" hint={`Đang dùng: ${runtime.effectiveBaseUrl}${runtime.keySource === 'env' ? ' (từ biến môi trường)' : ''}`}>
            <TextInput value={draft.ai.baseUrl} mono onChange={(value) => patchSection('ai', { baseUrl: value })} placeholder="https://api.openai.com/v1" />
          </Field>
          <Field label="Model phân tích" hint="Cần model có vision để đọc màn hình">
            <TextInput value={draft.ai.model} mono onChange={(value) => patchSection('ai', { model: value })} placeholder={runtime.effectiveModel} />
          </Field>
          <Field label="Model ghi âm → chữ" hint="Dùng cho chiến lược transcribe_first">
            <TextInput value={draft.ai.sttModel} mono onChange={(value) => patchSection('ai', { sttModel: value })} />
          </Field>
          <Field label="Cách gửi giọng nói">
            <Segmented
              value={draft.ai.strategy}
              onChange={(value) => patchSection('ai', { strategy: value })}
              options={[
                { value: 'multimodal', label: 'Audio + ảnh, 1 lượt gọi' },
                { value: 'transcribe_first', label: 'Chữ hoá trước' }
              ]}
            />
          </Field>
          <Field label="Reasoning effort" hint="Để mặc định nếu model không hỗ trợ">
            <Select
              value={draft.ai.reasoningEffort}
              onChange={(value) => patchSection('ai', { reasoningEffort: value as AppSettings['ai']['reasoningEffort'] })}
              options={[
                { value: 'default', label: 'Mặc định của model' },
                { value: 'minimal', label: 'minimal' },
                { value: 'low', label: 'low' },
                { value: 'medium', label: 'medium' },
                { value: 'high', label: 'high' }
              ]}
            />
          </Field>
          <div className="field-row">
            <Field label="Max tokens">
              <NumberInput value={draft.ai.maxTokens} min={128} max={8000} step={64} onChange={(value) => patchSection('ai', { maxTokens: value })} />
            </Field>
            <Field label="Timeout (ms)">
              <NumberInput value={draft.ai.timeoutMs} min={5000} max={180000} step={5000} onChange={(value) => patchSection('ai', { timeoutMs: value })} />
            </Field>
          </div>
        </div>

        {models?.models.length ? (
          <div className="model-picker">
            <p className="detail-label">Model từ endpoint ({models.models.length})</p>
            <div className="model-chips">
              {models.models.map((model) => (
                <button
                  type="button"
                  key={model.id}
                  className={`chip ${model.id === draft.ai.model ? 'is-active' : ''}`}
                  onClick={() => patchSection('ai', { model: model.id })}
                  title={model.vision ? 'Hỗ trợ vision' : 'Không thấy đánh dấu vision'}
                >
                  {model.id}
                  {model.vision ? <span className="chip-tag">👁</span> : null}
                </button>
              ))}
            </div>
          </div>
        ) : null}

        {lastTest ? <p className={`test-result ${lastTest.startsWith('OK') ? 'tone-ok' : 'tone-error'}`}>{lastTest}</p> : null}

        <div className="api-key">
          <Field
            label="API key"
            hint={
              runtime.hasKey
                ? `Đang dùng: ${runtime.keySource === 'vault' ? 'kho mã hoá của hệ điều hành' : 'biến môi trường'}. Key mới sẽ ghi đè.`
                : runtime.secureStorage
                  ? 'Chưa có key. Key được mã hoá trước khi ghi đĩa.'
                  : 'Chưa có key. Hệ thống này không có safeStorage nên hãy dùng biến môi trường AIBUBBLE_API_KEY.'
            }
          >
            <div className="row-gap">
              <TextInput value={keyValue} type="password" mono onChange={setKeyValue} placeholder="sk-..." />
              <Button
                variant="primary"
                disabled={!keyValue.trim() || !runtime.secureStorage}
                onClick={async () => {
                  await actions.setApiKey(keyValue)
                  setKeyValue('')
                  notify('Đã lưu API key', 'ok')
                }}
              >
                Lưu key
              </Button>
              <Button
                variant="danger"
                disabled={!runtime.hasKey || runtime.keySource !== 'vault'}
                onClick={async () => {
                  await actions.clearApiKey()
                  notify('Đã xoá API key khỏi kho', 'info')
                }}
              >
                Xoá key
              </Button>
            </div>
          </Field>
        </div>

        <Field label="System prompt" hint="Quy định cách AI đọc màn hình và trả lời">
          <TextArea value={draft.ai.systemPrompt} rows={7} onChange={(value) => patchSection('ai', { systemPrompt: value })} />
        </Field>
      </Card>

      <Card title="Phím nóng" subtitle="Bật/tắt một phiên nghe + nhìn màn hình">
        <div className="grid-2">
          <Field label="Bật phím nóng">
            <Toggle checked={draft.hotkey.enabled} onChange={(value) => patchSection('hotkey', { enabled: value })} label={draft.hotkey.enabled ? 'Đang bật' : 'Đang tắt'} />
          </Field>
          <Field label="Kiểu bấm" hint="Bấm đúp an toàn hơn khi bạn vẫn gõ phím này trong văn bản">
            <Segmented
              value={draft.hotkey.mode}
              onChange={(value) => patchSection('hotkey', { mode: value })}
              options={[
                { value: 'double_tap', label: 'Bấm đúp nhanh' },
                { value: 'single_tap', label: 'Bấm một lần' }
              ]}
            />
          </Field>
          <Field label="Phím kích hoạt" hint={runtime.hotkey.detail}>
            <Select
              value={draft.hotkey.keyId}
              onChange={(value) => patchSection('hotkey', { keyId: value })}
              options={HOTKEY_KEYS.map((option) => ({ value: option.id, label: option.label }))}
            />
          </Field>
          <Field
            label="Phím tuỳ chọn"
            hint={
              draft.hotkey.keyId === 'custom' && draft.hotkey.customKeycode
                ? `Đang gán: ${draft.hotkey.customKeyLabel || guessKeyName(draft.hotkey.customKeycode)} (mã ${draft.hotkey.customKeycode})`
                : 'Dùng cho Fn hoặc phím media mà hệ thống không có trong danh sách'
            }
          >
            <div className="row-gap">
              <Button variant={learning ? 'primary' : 'ghost'} onClick={() => void actions.learnKey(true)}>
                {learning ? 'Đang chờ bạn bấm phím…' : 'Học phím'}
              </Button>
              {learning ? <Button onClick={() => void actions.learnKey(false)}>Huỷ</Button> : null}
            </div>
          </Field>
          <Field label="Phím dự phòng (globalShortcut)" hint="Luôn chạy được kể cả khi hook bàn phím bị chặn">
            <TextInput value={draft.hotkey.fallbackShortcut} mono onChange={(value) => patchSection('hotkey', { fallbackShortcut: value })} placeholder="Alt+Shift+Space" />
          </Field>
          <Field label="Bật phím dự phòng">
            <Toggle
              checked={draft.hotkey.fallbackEnabled}
              onChange={(value) => patchSection('hotkey', { fallbackEnabled: value })}
              label={draft.hotkey.fallbackEnabled ? `Đang bật: ${draft.hotkey.fallbackShortcut}` : 'Đang tắt'}
            />
          </Field>
        </div>
        {HOTKEY_KEYS.find((option) => option.id === draft.hotkey.keyId)?.hint ? (
          <p className="note">{HOTKEY_KEYS.find((option) => option.id === draft.hotkey.keyId)?.hint}</p>
        ) : null}
      </Card>

      <Card title="Nghe và nhìn" subtitle="Những gì app gửi lên AI khi bạn bấm phím">
        <div className="grid-2">
          <Field label="Chụp màn hình kèm theo">
            <Toggle
              checked={draft.capture.includeScreenshot}
              onChange={(value) => patchSection('capture', { includeScreenshot: value })}
              label={draft.capture.includeScreenshot ? 'Bật' : 'Tắt (chỉ nghe)'}
            />
          </Field>
          <Field label="Chọn màn hình">
            <Segmented
              value={draft.capture.display}
              onChange={(value) => patchSection('capture', { display: value })}
              options={[
                { value: 'cursor', label: 'Nơi con trỏ đang ở' },
                { value: 'primary', label: 'Màn hình chính' }
              ]}
            />
          </Field>
          <Field label="Bề rộng tối đa (px)" hint="Ảnh được thu nhỏ trước khi gửi để tiết kiệm token">
            <NumberInput value={draft.capture.maxWidth} min={480} max={7680} step={80} onChange={(value) => patchSection('capture', { maxWidth: value })} />
          </Field>
          <Field label="Chất lượng JPEG">
            <NumberInput value={draft.capture.jpegQuality} min={40} max={98} step={1} onChange={(value) => patchSection('capture', { jpegQuality: value })} />
          </Field>
          <Field label="Giới hạn ghi âm (giây)">
            <NumberInput
              value={draft.capture.maxRecordSeconds}
              min={3}
              max={300}
              step={1}
              onChange={(value) => patchSection('capture', { maxRecordSeconds: value })}
            />
          </Field>
          <Field label="Thiết bị ghi âm" hint={devices.length ? `${devices.length} mic khả dụng` : 'Cấp quyền mic để thấy tên thiết bị'}>
            <Select
              value={draft.capture.deviceId}
              onChange={(value) => patchSection('capture', { deviceId: value })}
              options={[
                { value: 'default', label: 'Mặc định của hệ thống' },
                ...devices.map((device) => ({ value: device.deviceId, label: device.label }))
              ]}
            />
          </Field>
          <Field label="Phát tiếng bíp khi bật/tắt">
            <Toggle checked={draft.capture.beepOnToggle} onChange={(value) => patchSection('capture', { beepOnToggle: value })} label={draft.capture.beepOnToggle ? 'Bật' : 'Tắt'} />
          </Field>
        </div>
      </Card>

      <Card title="Bong bóng" subtitle="Giao diện nổi trên mọi ứng dụng">
        <div className="grid-2">
          <Field label="Tự đóng sau (giây)">
            <NumberInput
              value={draft.overlay.autoCollapseSeconds}
              min={4}
              max={300}
              onChange={(value) => patchSection('overlay', { autoCollapseSeconds: value })}
            />
          </Field>
          <Field label="Hiện bản ghi giọng nói">
            <Toggle
              checked={draft.overlay.showTranscript}
              onChange={(value) => patchSection('overlay', { showTranscript: value })}
              label={draft.overlay.showTranscript ? 'Hiện' : 'Ẩn'}
            />
          </Field>
          <Field label="Kích thước bong bóng" hint="Phóng to nội dung nếu màn hình độ phân giải cao">
            <NumberInput value={draft.overlay.scale} min={0.8} max={1.6} step={0.05} onChange={(value) => patchSection('overlay', { scale: value })} />
          </Field>
          <Field label="Vị trí" hint={draft.overlay.x !== null ? `x:${draft.overlay.x} y:${draft.overlay.y}` : 'Chưa lưu (mặc định góc dưới phải)'}>
            <div className="row-gap">
              <Button onClick={() => void actions.resetOverlayPosition()}>Về góc dưới phải</Button>
              <Button onClick={() => void actions.showOverlay(true)}>Hiện</Button>
              <Button onClick={() => void actions.showOverlay(false)}>Ẩn</Button>
            </div>
          </Field>
        </div>
        <p className="note">
          Linux (Wayland) và macOS có thể chặn window overlay hoặc hook bàn phím. Nếu bong bóng không hiện trên app toàn màn hình,
          hãy cấp quyền Screen Recording và khởi động lại app.
        </p>
      </Card>

      <Card title="Khác">
        <div className="grid-2">
          <Field label="Số phiên lưu lại">
            <NumberInput
              value={draft.general.keepHistoryCount}
              min={10}
              max={1000}
              step={10}
              onChange={(value) => patchSection('general', { keepHistoryCount: value })}
            />
          </Field>
          <Field label="Mở khi đăng nhập">
            <Toggle
              checked={draft.general.launchAtLogin}
              onChange={(value) => patchSection('general', { launchAtLogin: value })}
              label={draft.general.launchAtLogin ? 'Bật' : 'Tắt'}
            />
          </Field>
          <Field label="Khởi động mà không mở dashboard">
            <Toggle
              checked={draft.general.startHidden}
              onChange={(value) => patchSection('general', { startHidden: value })}
              label={draft.general.startHidden ? 'Ẩn dashboard' : 'Hiện dashboard'}
            />
          </Field>
          <Field label="Dữ liệu" hint={runtime.userData}>
            <div className="row-gap">
              <Button onClick={() => void actions.openDataFolder()}>Mở thư mục dữ liệu</Button>
            </div>
          </Field>
        </div>
      </Card>
    </div>
  )
}
import { HOTKEY_KEYS, type AppSettings } from '../../../../shared/types'
import type { AudioDeviceInfo } from '../../../../shared/bridge'
