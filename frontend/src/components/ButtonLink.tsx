import type { AnchorHTMLAttributes } from 'react'
import styles from './ButtonLink.module.css'

type Props = AnchorHTMLAttributes<HTMLAnchorElement> & {
  size?: 'sm' | 'md'
}

// A cream paper cut-out: it lifts on hover and presses flat into the page on
// click, the same hard offset shadow the film's pieces cast.
export function ButtonLink({ size = 'md', className, ...rest }: Props) {
  const cls = [styles.button, styles[size], className].filter(Boolean).join(' ')
  return <a className={cls} {...rest} />
}
