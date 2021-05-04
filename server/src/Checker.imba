import {Component} from './Component'
import type {Program,TypeChecker} from 'typescript'
import * as ts from 'typescript'
import { tsSymbolFlagsToKindString } from './utils'
import {Sym,Node as ImbaNode} from 'imba/program'

const SymbolObject = ts.objectAllocator.getSymbolConstructor!
const TypeObject = ts.objectAllocator.getTypeConstructor!
const NodeObject = ts.objectAllocator.getNodeConstructor!
const SourceFile = ts.objectAllocator.getSourceFileConstructor!
const Signature = ts.objectAllocator.getSignatureConstructor!


const SF = ts.SymbolFlags

extend class NodeObject

	# signature
	def labelSignature
		'()'

	get #sourceFile
		let curr = self
		while curr
			# console.log 'check curr',curr,SourceFile
			if curr isa SourceFile
				return curr
			curr = curr.parent
		return null
		

extend class SymbolObject

	get function?
		flags & ts.SymbolFlags.Function

	get pascal?
		let chr = escapedName.charCodeAt(0)
		return chr >= 65 && 90 >= chr

	get modifier?
		parent and parent.escapedName.indexOf('EventModifiers') >= 0

	get tagname?
		component? or parent and (/ImbaHTMLTags|HTMLElementTagNameMap/).test(parent.escapedName)

	get mapped?
		parent and (/HTMLElementTagNameMap|GlobalEventHandlersEventMap/).test(parent.escapedName)

	get component?
		escapedName.indexOf('$$TAG$$') > 0

	get localcomponent?
		component? and pascal?

	get typeName
		if mapped?
			declarations[0].type.typeName.escapedText
		else
			''

	get sourceFile
		if component?
			valueDeclaration.#sourceFile
		else
			null

	get details
		let name = escapedName
		let meta = #meta ||= {}
		if name.indexOf('$$TAG$$') > 0
			meta.component = yes
			meta.tag = yes
			name = name.slice(0,-7).replace(/\_/g,'-')
		if name.indexOf('_$SYM$_') == 0
			name = name.split("_$SYM$_").join("#")
			meta.internal = yes
		meta.name = name
		return meta
		
	get internal?
		escapedName.indexOf("__@") == 0

	get label
		details.name

	get typeSymbol
		type..symbol or self

	def doctag name
		#doctags ||= getJsDocTags!
		for item in #doctags
			if item.name == name
				return item.text or true
		return null

	def doctags query = /.*/
		#doctags ||= getJsDocTags!
		#doctags.filter do(item)
			let match = item.name + ' ' + item.text or ''
			!!query.test(match)
			
	def parametersToString
		if let decl = valueDeclaration
			let pars = decl.parameters.map do
					let out = $1.name.escapedText
					out += '?' if $1.questionToken
					return out

			return '(' + pars.join(', ') + ')'
		return ''
		

extend class Signature
	def toImbaTypeString
		let parts = []
		for item in parameters
			let name = item.escapedName
			let typ = item.type and checker.typeToString(item.type) or ''
			parts.push(name)
		return '(' + parts.join(', ') + ')'

extend class TypeObject
	def parametersToString
		# let str = checker.typeToString(item.type)
		# if callSignatures[0]
		if symbol
			return symbol.parametersToString!

		return ''


# wrapper for ts symbol / type with added info
 

export class ProgramSnapshot < Component

	checker\TypeChecker

	constructor program, file = null
		super()
		program = program
		checker = program.getTypeChecker!
		self.file = #file = file
		#blank = file or program.getSourceFiles()[0]
		#typeCache = {}
		
		self.SF = SF
		self.ts = ts

	# get checker
	#	#checker ||= program.getTypeChecker!

	get basetypes
		#basetypes ||= {
			string: checker.getStringType!
			number: checker.getNumberType!
			any: checker.getAnyType!
			void: checker.getVoidType!
			"undefined": checker.getUndefinedType!
		}

	def arraytype inner
		checker.createArrayType(inner or basetypes.any)

	def resolve name,types = SF.All
		let sym = checker.resolveName(name,self.fileRef(#file),symbolFlags(types),false)
		return sym
		
	def parseType string, token, returnAst = no
		
		string = string.slice(1) if string[0] == '\\'
		if let cached = #typeCache[string]
			return cached
		
		let ast
		try
			ast = ts.parseJSDocTypeExpressionForTests(string,0,string.length).jsDocTypeExpression.type
			ast.resolved = resolveTypeExpression(ast,{text: string},token)
			return ast if returnAst
			return #typeCache[string] = ast.resolved
		catch e
			console.log 'parseType error',e,ast
	
	def resolveTypeExpression expr, source, ctx
		let val = expr.getText(source)
		
		if expr.elements
			let types = expr.elements.map do resolveTypeExpression($1,source,ctx)
			return checker.createArrayType(types[0])
		
		if expr.elementType
			let type = resolveTypeExpression(expr.elementType,source,ctx)
			return checker.createArrayType(type)
		
		if expr.types
			let types = expr.types.map do resolveTypeExpression($1,source,ctx)
			console.log 'type unions',types
			return checker.getUnionType(types)
		if expr.typeName
			let typ = local(expr.typeName.escapedText,#file,'Type')
			if typ
				return checker.getDeclaredTypeOfSymbol(typ)
				return type(typ)
		elif basetypes[val]
			return basetypes[val]
		
		
	

	def local name, target = #file, types = SF.All
		let sym = checker.resolveName(name,loc(target),symbolFlags(types),false)
		return sym

	def symbolFlags val
		if typeof val == 'string'
			val = SF[val]
		return val

	def signature item
		let typ = type(item)
		let signatures = checker.getSignaturesOfType(typ,0)
		return signatures[0]

	def string item
		let parts
		if item isa Signature
			parts = ts.signatureToDisplayParts(checker,item)
		
		if parts isa Array
			return util.displayPartsToString(parts)
		return ''

	def fileRef value
		return undefined unless value
		if value.fileName
			value = value.fileName

		if typeof value == 'string'
			program.getSourceFileByPath(value)
		else
			value

	def loc item
		return undefined unless item
		if typeof item == 'number'
			return ts.findPrecedingToken(item,loc(#file))
		if item.fileName
			return program.getSourceFileByPath(item.fileName)
		if item isa SymbolObject
			return item.valueDeclaration
		return item


	def type item
		if typeof item == 'string'
			if item.indexOf('.') >= 0
				item = item.split('.')
			else
				item = resolve(item)

		if item isa Array
			let base = type(item[0])
			for entry,i in item when i > 0
				base = type(member(base,entry))
			item = base

		if item isa SymbolObject
			# console.log 'get the declared type of the symbol',item,item.flags
			if item.flags & SF.Interface
				
				item.type ||= checker.getDeclaredTypeOfSymbol(item)
			item.type ||= checker.getTypeOfSymbolAtLocation(item,loc(#file or #blank))
			return item.type

		if item isa TypeObject
			return item

		if item isa Signature
			return item.getReturnType!

	def sym item
		if typeof item == 'string'
			if item.indexOf('.') >= 0
				item = item.split('.')
			else
				item = resolve(item)

		if item isa Array
			let base = sym(item[0])
			for entry,i in item when i > 0
				base = sym(member(base,entry))
			item = base

		if item isa SymbolObject
			return item

		if item isa TypeObject and item.symbol
			return item.symbol

	def locals source = #file
		let file = fileRef(source)
		let locals = file.locals.values!
		return Array.from(locals)
	
	def props item, withTypes = no
		let typ = type(item)
		return [] unless typ

		let props = typ.getProperties!
		if withTypes
			for item in props
				type(item)
		return props

	def propnames item
		let values = type(item).getProperties!
		values.map do $1.escapedName

	def member item, name
		return unless item

		if typeof name == 'number'
			name = String(name)

		if name isa Array
			console.log 'access the signature of this type!!',item,name

		# console.log 'member',item,name
		let key = name.replace(/\!$/,'')
		let typ = type(item)
		let sym = typ.getProperty(key)
		
		if key == '__@iterable'
			console.log "CHECK TYPE",item,name
			let resolvedType = checker.getApparentType(typ)
			sym = resolvedType.members.get('__@iterator')
			return type(signature(sym)).resolvedTypeArguments[0]
			#  iter.getCallSignatures()[0].getReturnType()
			
		if sym == undefined
			let resolvedType = checker.getApparentType(typ)
			sym = resolvedType.members.get(name)
			
			if name.match(/^\d+$/)
				sym ||= typ.getNumberIndexType!
			else
				sym ||= typ.getStringIndexType!

		if key !== name
			sym = signature(sym)
		return sym

	def wrap value
		value

	def inspect value
		# for item in value
		#	devlog item.label,item
		value

	get globals do resolve('globalThis')
	get win do resolve('window')
	get doc do resolve('document')

	def path path, base = null
		yes

	def resolvePath tok, doc
		let sym = tok.symbol
		let typ = tok.type

		if tok isa Array
			return tok.map do resolvePath($1,doc)
		
		if typeof tok == 'number' or typeof tok == 'string'
			
			if typeof tok == 'string' and tok[0] == '\\'
				return parseType(tok,null)

			return tok

		if tok isa ImbaNode
			
			if tok.type == 'type'
				let val = String(tok)
				return parseType(val,tok)
				# console.log 'DATATYPE',tok.datatype,val
				# we do need to resolve the type to
				# if basetypes[val.slice(1)]
				#	return basetypes[val.slice(1)]
			
			if tok.match('value')
				let end = tok.end.prev
				end = end.prev if end.match('br')
				tok = end
			# console.log 'checking imba node!!!',tok

		if tok isa Sym
			let typ = tok.datatype
			if typ
				return resolvePath(typ,doc)
				
			if tok.#tsym
				return tok.#tsym

			if tok.body
				# doesnt make sense
				return resolveType(tok.body,doc)

		let value = tok.pops

		if value
			if value.match('index')
				return [resolvePath(value.start.prev),'0']

			if value.match('args')
				
				let res = type(signature(resolvePath(value.start.prev),[]))
				devlog 'token match args!!!',res
				return res

			if value.match('array')
				# console.log 'found array!!!',tok.pops
				return arraytype(basetypes.any)

		if tok.match('tag.event.start')
			return 'ImbaEvents'

		if tok.match('tag.event.name')
			# maybe prefix makes sense to keep after all now?
			return ['ImbaEvents',tok.value]

		if tok.match('tag.event-modifier.start')
			# maybe prefix makes sense to keep after all now?
			return [['ImbaEvents',tok.context.name],'MODIFIERS']
			# return ['ImbaEvents',tok.value]
		
		# if this is a call
		if typ == ')' and tok.start
			return [resolvePath(tok.start.prev),'!']

		if tok.match('number')
			return basetypes.number

		elif tok.match('string')
			return basetypes.string

		if tok.match('operator.access')
			devlog 'resolve before operator.oacecss',tok.prev
			return resolvePath(tok.prev,doc)

		if tok.type == 'self'
			return tok.context.selfScope.selfPath

		if tok.match('identifier')
			# what if it is inside an object that is flagged as an assignment?
			
			if tok.value == 'global'
				return 'globalThis'

			if !sym
				let scope = tok.context.selfScope

				if tok.value == 'self'
					return scope.selfPath

				let accessor = tok.value[0] == tok.value[0].toLowerCase!
				if accessor
					return [scope.selfPath,tok.value]
				else
					return type(self.local(tok.value))

			return resolveType(sym,doc)

		if tok.match('accessor')
			# let lft = tok.prev.prev
			return [resolvePath(tok.prev,doc),tok.value]

	def resolveType tok, doc
		let paths = resolvePath(tok,doc)
		# console.log 'resolving paths',paths
		return type(paths)