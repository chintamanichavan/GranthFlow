'use client'

import { useSession, signOut } from 'next-auth/react'
import Link from 'next/link'
import { useTheme } from 'next-themes'
import { useState } from 'react'

export function Navigation() {
  const { data: session } = useSession()
  const { theme, setTheme } = useTheme()
  const [isMenuOpen, setIsMenuOpen] = useState(false)

  return (
    <nav className="bg-white dark:bg-secondary-800 shadow-sm">
      <div className="container mx-auto px-4">
        <div className="flex justify-between items-center h-16">
          {/* Logo */}
          <Link href="/" className="text-2xl font-bold text-primary-600">
            GranthFlow
          </Link>

          {/* Navigation Links */}
          <div className="hidden md:flex items-center space-x-8">
            <Link
              href="/explore"
              className="text-secondary-600 hover:text-primary-600 dark:text-secondary-300 dark:hover:text-primary-400"
            >
              Explore
            </Link>
            <Link
              href="/library"
              className="text-secondary-600 hover:text-primary-600 dark:text-secondary-300 dark:hover:text-primary-400"
            >
              My Library
            </Link>
            {session ? (
              <div className="relative">
                <button
                  onClick={() => setIsMenuOpen(!isMenuOpen)}
                  className="flex items-center space-x-2 text-secondary-600 hover:text-primary-600 dark:text-secondary-300 dark:hover:text-primary-400"
                >
                  <span>{session.user?.name || session.user?.email}</span>
                  <svg
                    className="w-4 h-4"
                    fill="none"
                    stroke="currentColor"
                    viewBox="0 0 24 24"
                  >
                    <path
                      strokeLinecap="round"
                      strokeLinejoin="round"
                      strokeWidth={2}
                      d="M19 9l-7 7-7-7"
                    />
                  </svg>
                </button>
                {isMenuOpen && (
                  <div className="absolute right-0 mt-2 w-48 bg-white dark:bg-secondary-800 rounded-lg shadow-lg py-2">
                    <Link
                      href="/profile"
                      className="block px-4 py-2 text-secondary-600 hover:bg-secondary-100 dark:text-secondary-300 dark:hover:bg-secondary-700"
                    >
                      Profile
                    </Link>
                    <button
                      onClick={() => signOut()}
                      className="block w-full text-left px-4 py-2 text-secondary-600 hover:bg-secondary-100 dark:text-secondary-300 dark:hover:bg-secondary-700"
                    >
                      Sign Out
                    </button>
                  </div>
                )}
              </div>
            ) : (
              <Link
                href="/auth/signin"
                className="btn-primary"
              >
                Sign In
              </Link>
            )}
            <button
              onClick={() => setTheme(theme === 'dark' ? 'light' : 'dark')}
              className="p-2 rounded-lg text-secondary-600 hover:bg-secondary-100 dark:text-secondary-300 dark:hover:bg-secondary-700"
            >
              {theme === 'dark' ? '🌞' : '🌙'}
            </button>
          </div>

          {/* Mobile Menu Button */}
          <button
            onClick={() => setIsMenuOpen(!isMenuOpen)}
            className="md:hidden p-2 rounded-lg text-secondary-600 hover:bg-secondary-100 dark:text-secondary-300 dark:hover:bg-secondary-700"
          >
            <svg
              className="w-6 h-6"
              fill="none"
              stroke="currentColor"
              viewBox="0 0 24 24"
            >
              <path
                strokeLinecap="round"
                strokeLinejoin="round"
                strokeWidth={2}
                d="M4 6h16M4 12h16M4 18h16"
              />
            </svg>
          </button>
        </div>

        {/* Mobile Menu */}
        {isMenuOpen && (
          <div className="md:hidden py-4">
            <Link
              href="/explore"
              className="block py-2 text-secondary-600 hover:text-primary-600 dark:text-secondary-300 dark:hover:text-primary-400"
            >
              Explore
            </Link>
            <Link
              href="/library"
              className="block py-2 text-secondary-600 hover:text-primary-600 dark:text-secondary-300 dark:hover:text-primary-400"
            >
              My Library
            </Link>
            {session ? (
              <>
                <Link
                  href="/profile"
                  className="block py-2 text-secondary-600 hover:text-primary-600 dark:text-secondary-300 dark:hover:text-primary-400"
                >
                  Profile
                </Link>
                <button
                  onClick={() => signOut()}
                  className="block w-full text-left py-2 text-secondary-600 hover:text-primary-600 dark:text-secondary-300 dark:hover:text-primary-400"
                >
                  Sign Out
                </button>
              </>
            ) : (
              <Link
                href="/auth/signin"
                className="block py-2 text-secondary-600 hover:text-primary-600 dark:text-secondary-300 dark:hover:text-primary-400"
              >
                Sign In
              </Link>
            )}
            <button
              onClick={() => setTheme(theme === 'dark' ? 'light' : 'dark')}
              className="block w-full text-left py-2 text-secondary-600 hover:text-primary-600 dark:text-secondary-300 dark:hover:text-primary-400"
            >
              {theme === 'dark' ? '🌞 Light Mode' : '🌙 Dark Mode'}
            </button>
          </div>
        )}
      </div>
    </nav>
  )
} 