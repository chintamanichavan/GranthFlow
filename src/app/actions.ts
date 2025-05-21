'use server'

import { getServerSession } from 'next-auth'
import { PrismaClient } from '@prisma/client'
import { revalidatePath } from 'next/cache'

const prisma = new PrismaClient()

export async function addBookToLibrary(bookId: string) {
  const session = await getServerSession()

  if (!session?.user?.email) {
    throw new Error('Not authenticated')
  }

  try {
    await prisma.user.update({
      where: { email: session.user.email },
      data: {
        books: {
          connect: { id: bookId },
        },
      },
    })

    revalidatePath('/library')
    revalidatePath('/explore')
  } catch (error) {
    console.error('Error adding book to library:', error)
    throw new Error('Failed to add book to library')
  }
}

export async function updateReadingProgress(bookId: string, page: number) {
  const session = await getServerSession()

  if (!session?.user?.email) {
    throw new Error('Not authenticated')
  }

  try {
    await prisma.readingProgress.upsert({
      where: {
        userId_bookId: {
          userId: session.user.id,
          bookId,
        },
      },
      update: {
        page,
      },
      create: {
        userId: session.user.id,
        bookId,
        page,
      },
    })

    revalidatePath('/library')
  } catch (error) {
    console.error('Error updating reading progress:', error)
    throw new Error('Failed to update reading progress')
  }
}

export async function addBookmark(bookId: string, page: number) {
  const session = await getServerSession()

  if (!session?.user?.email) {
    throw new Error('Not authenticated')
  }

  try {
    await prisma.bookmark.create({
      data: {
        userId: session.user.id,
        bookId,
        page,
      },
    })

    revalidatePath('/library')
  } catch (error) {
    console.error('Error adding bookmark:', error)
    throw new Error('Failed to add bookmark')
  }
}

export async function addNote(bookId: string, page: number, content: string) {
  const session = await getServerSession()

  if (!session?.user?.email) {
    throw new Error('Not authenticated')
  }

  try {
    await prisma.note.create({
      data: {
        userId: session.user.id,
        bookId,
        page,
        content,
      },
    })

    revalidatePath('/library')
  } catch (error) {
    console.error('Error adding note:', error)
    throw new Error('Failed to add note')
  }
} 