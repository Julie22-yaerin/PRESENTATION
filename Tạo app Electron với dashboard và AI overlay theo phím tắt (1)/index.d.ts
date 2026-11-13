import type { BubbleBridge } from '../shared/bridge'

declare global {
  interface Window {
    /** The only bridge between renderers and the main process. */
    bubble: BubbleBridge
  }
}

export {}
