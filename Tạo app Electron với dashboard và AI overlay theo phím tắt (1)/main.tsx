import { createRoot } from 'react-dom/client'
import '../styles/theme.css'
import '../styles/overlay.css'
import { Bubble } from './Bubble'

const container = document.getElementById('root')
if (!container) throw new Error('Overlay root missing')

createRoot(container).render(<Bubble />)
