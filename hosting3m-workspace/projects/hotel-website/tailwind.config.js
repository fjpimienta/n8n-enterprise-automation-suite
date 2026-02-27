/** @type {import('tailwindcss').Config} */
module.exports = {
    content: [
        "projects/hotel-website/src/**/*.{html,ts}",
        "projects/ui-chat/src/**/*.{html,ts}"
    ],
    theme: {
        extend: {
            colors: {
                eco: { 50: '#f2f6f4', 100: '#e1ede5', 500: '#4a7c59', 700: '#2d4a36', 900: '#1a2b1f' },
                tierra: { 100: '#f5ebe0', 500: '#d4a373', 900: '#8b5a2b' }
            },
            fontFamily: {
                sans: ['Inter', 'sans-serif'],
                serif: ['Merriweather', 'serif'],
            }
        }
    },
    plugins: [],
}