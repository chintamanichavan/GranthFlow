import Link from 'next/link'

export default function Home() {
  return (
    <main className="min-h-screen">
      {/* Hero Section */}
      <section className="bg-gradient-to-b from-primary-50 to-white dark:from-secondary-900 dark:to-secondary-800 py-20">
        <div className="container mx-auto px-4">
          <div className="max-w-3xl mx-auto text-center">
            <h1 className="text-4xl md:text-6xl font-bold text-secondary-900 dark:text-white mb-6">
              Your Digital Reading Companion
            </h1>
            <p className="text-xl text-secondary-600 dark:text-secondary-300 mb-8">
              Discover, read, and organize your books in one beautiful place.
              Inspired by Apple Books, built for the web.
            </p>
            <div className="flex flex-col sm:flex-row gap-4 justify-center">
              <Link
                href="/auth/signin"
                className="btn-primary text-lg px-8 py-3"
              >
                Get Started
              </Link>
              <Link
                href="/explore"
                className="btn-secondary text-lg px-8 py-3"
              >
                Explore Books
              </Link>
            </div>
          </div>
        </div>
      </section>

      {/* Features Section */}
      <section className="py-20">
        <div className="container mx-auto px-4">
          <h2 className="text-3xl font-bold text-center mb-12 text-secondary-900 dark:text-white">
            Why Choose GranthFlow?
          </h2>
          <div className="grid md:grid-cols-3 gap-8">
            <div className="card">
              <div className="text-primary-600 text-4xl mb-4">📚</div>
              <h3 className="text-xl font-semibold mb-2 text-secondary-900 dark:text-white">
                Extensive Library
              </h3>
              <p className="text-secondary-600 dark:text-secondary-300">
                Access thousands of books across various genres and categories.
              </p>
            </div>
            <div className="card">
              <div className="text-primary-600 text-4xl mb-4">📱</div>
              <h3 className="text-xl font-semibold mb-2 text-secondary-900 dark:text-white">
                Read Anywhere
              </h3>
              <p className="text-secondary-600 dark:text-secondary-300">
                Enjoy your books on any device with our responsive web interface.
              </p>
            </div>
            <div className="card">
              <div className="text-primary-600 text-4xl mb-4">📝</div>
              <h3 className="text-xl font-semibold mb-2 text-secondary-900 dark:text-white">
                Smart Features
              </h3>
              <p className="text-secondary-600 dark:text-secondary-300">
                Take notes, bookmark pages, and track your reading progress.
              </p>
            </div>
          </div>
        </div>
      </section>
    </main>
  )
} 