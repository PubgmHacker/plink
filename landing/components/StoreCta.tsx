import type { ReactNode } from 'react';
import { STORE_CTA } from '@/lib/constants';

type Props = {
  className?: string;
  /** Иконка перед подписью (например, логотип Apple). */
  icon?: ReactNode;
  /**
   * Своя подпись для состояния «приложение в App Store». В остальных состояниях
   * всегда показывается подпись помощника («Открыть в TestFlight» / «Скоро в
   * App Store»), чтобы кнопка не обещала того, чего нет.
   */
  label?: string;
};

/**
 * Единственный способ отрисовать кнопку «Скачать». Пока ссылки на магазин нет,
 * это не ссылка, а неактивный элемент — без href на заглушку.
 */
export default function StoreCta({ className, icon, label }: Props) {
  const text = STORE_CTA.live && label ? label : STORE_CTA.label;

  if (!STORE_CTA.href) {
    return (
      <span
        aria-disabled="true"
        className={`${className ?? ''} cursor-default select-none opacity-80`}
      >
        {icon}
        {text}
      </span>
    );
  }

  return (
    <a href={STORE_CTA.href} target="_blank" rel="noopener noreferrer" className={className}>
      {icon}
      {text}
    </a>
  );
}
