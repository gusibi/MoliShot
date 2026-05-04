/** @type {import('tailwindcss').Config} */
export default {
  darkMode: 'class',
  content: ['./src/**/*.{astro,html,js,jsx,md,mdx,svelte,ts,tsx,vue}'],
  theme: {
    extend: {
      colors: {
        accent: {
          DEFAULT: '#F07855',
          hover: '#F59075',
          light: '#FFB088',
          glow: 'rgba(240,120,85,0.15)',
        },
        surf: { DEFAULT: '#FCFAF5', elevated: '#F7F4EF', card: '#FFFFFF' },
        mute: { DEFAULT: '#5a5a5a', dim: '#8a8a8a' },
        bord: { DEFAULT: '#E8E2D6', light: '#F0EBE0' },
      },
      fontFamily: {
        mono: ['"JetBrains Mono"', '"SF Mono"', '"Fira Code"', 'monospace'],
        sans: ['"Space Grotesk"', '-apple-system', 'BlinkMacSystemFont', 'sans-serif'],
      },
      borderRadius: { lg: '16px' },
    },
  },
  plugins: [],
};
