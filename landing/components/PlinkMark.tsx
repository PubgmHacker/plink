/**
 * Знак Plink — векторные контуры эталонного лок-апа (brand/plink-mark.svg).
 * Координаты — в системе макета 1056×1008; знак занимает рамку 388…738 × 81…541,
 * viewBox обрезан ровно по ней. Цвета — константы бренда, темы сайта не касаются.
 */
const MARK_A =
  'M422.7 225.2C401.2 211.2 388.3 183.2 388.3 160.9L388.3 160.9C388.3 93.6 446.2 58.0 507.6 97.9L696.1 220.4C752.9 257.4 751.8 356.9 695.3 389.7L592.0 449.6C576.7 458.4 562.5 448.7 562.5 433.8L562.5 340.8C562.5 328.3 554.8 311.0 540.8 301.9Z';
const MARK_B =
  'M492.9 338.0C511.1 327.8 527.3 335.7 527.3 360.7L527.3 471.9C527.3 505.4 504.6 541.2 460.6 541.2L460.6 541.2C416.8 541.2 396.1 508.0 396.1 474.2L396.1 422.8C396.1 410.9 407.9 385.9 424.1 376.8Z';

type Props = {
  /** Высота знака в px (ширина следует пропорции 350:460). */
  size?: number;
  className?: string;
  /** Уникальный префикс id для градиентов, если знаков на странице несколько. */
  id?: string;
  title?: string;
};

export default function PlinkMark({ size = 28, className, id = 'pm', title }: Props) {
  const w = (size * 350) / 460;
  return (
    <svg
      width={w}
      height={size}
      viewBox="388.33 81.2 350 460"
      className={className}
      role={title ? 'img' : undefined}
      aria-hidden={title ? undefined : true}
    >
      {title ? <title>{title}</title> : null}
      <defs>
        <linearGradient
          id={`${id}A`}
          gradientUnits="userSpaceOnUse"
          x1="613.5"
          y1="138.3"
          x2="509.5"
          y2="421.7"
        >
          <stop offset="0.0625" stopColor="#8f44f0" />
          <stop offset="0.1875" stopColor="#7a39f0" />
          <stop offset="0.3125" stopColor="#6931ef" />
          <stop offset="0.4375" stopColor="#5b29ee" />
          <stop offset="0.5625" stopColor="#4c21ed" />
          <stop offset="0.6875" stopColor="#4823ee" />
          <stop offset="0.8125" stopColor="#421ceb" />
          <stop offset="0.9375" stopColor="#4016ea" />
        </linearGradient>
        <linearGradient
          id={`${id}B`}
          gradientUnits="userSpaceOnUse"
          x1="547.4"
          y1="387.6"
          x2="396.6"
          y2="489.4"
        >
          <stop offset="0.0625" stopColor="#2c0688" />
          <stop offset="0.1875" stopColor="#290684" />
          <stop offset="0.3125" stopColor="#2e0687" />
          <stop offset="0.4375" stopColor="#320788" />
          <stop offset="0.5625" stopColor="#38088e" />
          <stop offset="0.6875" stopColor="#3c0990" />
          <stop offset="0.8125" stopColor="#440b97" />
          <stop offset="0.9375" stopColor="#500e9d" />
        </linearGradient>
        <linearGradient
          id={`${id}R`}
          gradientUnits="userSpaceOnUse"
          x1="613"
          y1="138"
          x2="510"
          y2="422"
        >
          <stop offset="0" stopColor="#eadfff" stopOpacity="0.6" />
          <stop offset="1" stopColor="#eadfff" stopOpacity="0.2" />
        </linearGradient>
        <clipPath id={`${id}C`}>
          <path d={MARK_A} />
        </clipPath>
      </defs>
      <path d={MARK_B} fill={`url(#${id}B)`} />
      <path d={MARK_A} fill={`url(#${id}A)`} />
      <path
        d={MARK_A}
        fill="none"
        stroke={`url(#${id}R)`}
        strokeWidth="3"
        clipPath={`url(#${id}C)`}
      />
    </svg>
  );
}
