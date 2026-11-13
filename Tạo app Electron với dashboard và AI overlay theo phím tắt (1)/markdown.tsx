import type { ReactNode } from 'react'

/**
 * Minimal markdown subset for AI answers: headings become emphasis, `code`,
 * **bold**, - lists and 1. lists. No raw HTML is ever emitted.
 */
function inline(text: string, keyBase: string): ReactNode[] {
  const nodes: ReactNode[] = []
  const pattern = /(`[^`]+`)|(\*\*[^*]+\*\*)|(_[^_]+_)/g
  let cursor = 0
  let match: RegExpExecArray | null
  let index = 0

  while ((match = pattern.exec(text)) !== null) {
    if (match.index > cursor) nodes.push(text.slice(cursor, match.index))
    const token = match[0]
    const key = `${keyBase}-${index++}`
    if (token.startsWith('`')) {
      nodes.push(
        <code key={key} className="md-code">
          {token.slice(1, -1)}
        </code>
      )
    } else if (token.startsWith('**')) {
      nodes.push(
        <strong key={key} className="md-strong">
          {token.slice(2, -2)}
        </strong>
      )
    } else {
      nodes.push(
        <em key={key} className="md-em">
          {token.slice(1, -1)}
        </em>
      )
    }
    cursor = match.index + token.length
  }
  if (cursor < text.length) nodes.push(text.slice(cursor))
  return nodes
}

export function Markdown({ source, className }: { source: string; className?: string }): ReactNode {
  const lines = source.replace(/\r/g, '').split('\n')
  const blocks: ReactNode[] = []
  let listItems: string[] = []
  let listOrdered = false

  const flushList = (): void => {
    if (!listItems.length) return
    const className = listOrdered ? 'md-ol' : 'md-ul'
    const items = listItems
    const key = `list-${blocks.length}`
    blocks.push(
      listOrdered ? (
        <ol key={key} className={className}>
          {items.map((item, index) => (
            <li key={index}>{inline(item, `${key}-${index}`)}</li>
          ))}
        </ol>
      ) : (
        <ul key={key} className={className}>
          {items.map((item, index) => (
            <li key={index}>{inline(item, `${key}-${index}`)}</li>
          ))}
        </ul>
      )
    )
    listItems = []
  }

  for (let lineIndex = 0; lineIndex < lines.length; lineIndex += 1) {
    const line = lines[lineIndex].trimEnd()
    if (!line.trim()) {
      flushList()
      continue
    }
    const bullet = /^\s*[-*•]\s+(.*)$/.exec(line)
    const numbered = /^\s*(?:\d+)[.)]\s+(.*)$/.exec(line)
    const heading = /^#{1,6}\s+(.*)$/.exec(line)

    if (bullet) {
      if (listOrdered) flushList()
      listItems.push(bullet[1])
      continue
    }
    if (numbered) {
      if (!listOrdered && listItems.length) flushList()
      listOrdered = true
      listItems.push(numbered[1])
      continue
    }
    flushList()
    listOrdered = false

    if (heading) {
      blocks.push(
        <p key={`h-${lineIndex}`} className="md-heading">
          {inline(heading[1], `h-${lineIndex}`)}
        </p>
      )
      continue
    }
    blocks.push(<p key={`p-${lineIndex}`}>{inline(line, `p-${lineIndex}`)}</p>)
  }
  flushList()

  return <div className={className}>{blocks}</div>
}
