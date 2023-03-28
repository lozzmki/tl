
local NM = os.getenv("NM") or "nm"

local c_preamble = [[

#include <lua.h>
#include <lualib.h>
#include <lauxlib.h>
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>

/* portable alerts, from srlua */
#ifdef _WIN32
#include <windows.h>
#define alert(message)  MessageBox(NULL, message, progname, MB_ICONERROR | MB_OK)
#define getprogname()   char name[MAX_PATH]; argv[0]= GetModuleFileName(NULL,name,sizeof(name)) ? name : NULL;
#else
#define alert(message)  fprintf(stderr,"%s: %s\n", progname, message)
#define getprogname()
#endif

static int registry_key;

/* fatal error, from srlua */
static void fatal(const char* message) {
   alert(message);
   exit(EXIT_FAILURE);
}

]]

local c_main = [[

/* custom package loader */
static int pkg_loader(lua_State* L) {
   lua_pushlightuserdata(L, (void*) &registry_key); /* modname ? registry_key */
   lua_rawget(L, LUA_REGISTRYINDEX);                /* modname ? modules */
   lua_pushvalue(L, -1);                            /* modname ? modules modules */
   lua_pushvalue(L, 1);                             /* modname ? modules modules modname */
   lua_gettable(L, -2);                             /* modname ? modules mod */
   if (lua_type(L, -1) == LUA_TNIL) {
      lua_pop(L, 1);                                /* modname ? modules */
      lua_pushvalue(L, 1);                          /* modname ? modules modname */
      lua_pushliteral(L, ".init");                  /* modname ? modules modname ".init" */
      lua_concat(L, 2);                             /* modname ? modules modname..".init" */
      lua_gettable(L, -2);                          /* modname ? mod */
   }
   return 1;
}

static void install_pkg_loader(lua_State* L) {
   lua_settop(L, 0);                                /* */
   lua_getglobal(L, "table");                       /* table */
   lua_getfield(L, -1, "insert");                   /* table table.insert */
   lua_getglobal(L, "package");                     /* table table.insert package */
   lua_getfield(L, -1, "searchers");                /* table table.insert package package.searchers */
   if (lua_type(L, -1) == LUA_TNIL) {
      lua_pop(L, 1);
      lua_getfield(L, -1, "loaders");               /* table table.insert package package.loaders */
   }
   lua_copy(L, 4, 3);                               /* table table.insert package.searchers */
   lua_settop(L, 3);                                /* table table.insert package.searchers */
   lua_pushnumber(L, 1);                            /* table table.insert package.searchers 1 */
   lua_pushcfunction(L, pkg_loader);                /* table table.insert package.searchers 1 pkg_loader */
   lua_call(L, 3, 0);                               /* table */
   lua_settop(L, 0);                                /* */
}

/* main script launcher, from srlua */
static int pmain(lua_State *L) {
   int argc = lua_tointeger(L, 1);
   char** argv = lua_touserdata(L, 2);
   int i;
   load_main(L);
   lua_createtable(L, argc, 0);
   for (i = 0; i < argc; i++) {
      lua_pushstring(L, argv[i]);
      lua_rawseti(L, -2, i);
   }
   lua_setglobal(L, "arg");
   luaL_checkstack(L, argc - 1, "too many arguments to script");
   for (i = 1; i < argc; i++) {
      lua_pushstring(L, argv[i]);
   }
   lua_call(L, argc - 1, 0);
   return 0;
}

/* error handler, from luac */
static int msghandler (lua_State *L) {
   /* is error object not a string? */
   const char *msg = lua_tostring(L, 1);
   if (msg == NULL) {
      /* does it have a metamethod that produces a string */
      if (luaL_callmeta(L, 1, "__tostring") && lua_type(L, -1) == LUA_TSTRING) {
         /* then that is the message */
         return 1;
      } else {
         msg = lua_pushfstring(L, "(error object is a %s value)", luaL_typename(L, 1));
      }
   }
   /* append a standard traceback */
   luaL_traceback(L, L, msg, 1);
   return 1;
}

/* main function, from srlua */
int main(int argc, char** argv) {
   lua_State* L;
   getprogname();
   if (argv[0] == NULL) {
      fatal("cannot locate this executable");
   }
   L = luaL_newstate();
   if (L == NULL) {
      fatal("not enough memory for state");
   }
   luaL_openlibs(L);
   install_pkg_loader(L);
   declare_libraries(L);
   declare_modules(L);
   lua_pushcfunction(L, &msghandler);
   lua_pushcfunction(L, &pmain);
   lua_pushinteger(L, argc);
   lua_pushlightuserdata(L, argv);
   if (lua_pcall(L, 2, 0, -4) != 0) {
      fatal(lua_tostring(L, -1));
   }
   lua_close(L);
   return EXIT_SUCCESS;
}

]]

local function reindent_c(input)
   local out = {}
   local indent = 0
   local previous_is_blank = true
   for line in input:gmatch("([^\n]*)") do
      line = line:match("^[ \t]*(.-)[ \t]*$")

      local is_blank = (#line == 0)
      local do_print =
         (not is_blank) or
         (not previous_is_blank and indent == 0)

      if line:match("^[})]") then
         indent = indent - 1
         if indent < 0 then indent = 0 end
      end
      if do_print then
         table.insert(out, string.rep("   ", indent))
         table.insert(out, line)
         table.insert(out, "\n")
      end
      if line:match("[{(]$") then
         indent = indent + 1
      end

      previous_is_blank = is_blank
   end
   return table.concat(out)
end

local hexdump
do
   local numtab = {}
   for i = 0, 255 do
     numtab[string.char(i)] = ("%-3d,"):format(i)
   end
   function hexdump(str)
      return (str:gsub(".", numtab):gsub(("."):rep(80), "%0\n"))
   end
end

local function bin2c_file(out, filename)
   local fd = io.open(filename, "rb")
   local content = fd:read("*a"):gsub("^#![^\n]+\n", "")
   fd:close()
   table.insert(out, ("static const unsigned char code[] = {"))
   table.insert(out, hexdump(content))
   table.insert(out, ("};"))
end

local function load_main(out, main_program, program_name)
   table.insert(out, [[static void load_main(lua_State* L) {]])
   bin2c_file(out, main_program)
   table.insert(out, ("if(luaL_loadbuffer(L, code, sizeof(code), %q) != LUA_OK) {"):format(program_name))
   table.insert(out, ("   fatal(lua_tostring(L, -1));"))
   table.insert(out, ("}"))
   table.insert(out, [[}]])
   table.insert(out, [[]])
end

local function declare_modules(out, basename, files)
   table.insert(out, [[
   static void declare_modules(lua_State* L) {
      lua_settop(L, 0);                                /* */
      lua_newtable(L);                                 /* modules */
      lua_pushlightuserdata(L, (void*) &registry_key); /* modules registry_key */
      lua_pushvalue(L, 1);                             /* modules registry_key modules */
      lua_rawset(L, LUA_REGISTRYINDEX);                /* modules */
   ]])
   for _, filename in ipairs(files) do
      if filename:match("%.lua$") then
         local name = filename:gsub("^" .. basename .. "/", "")
         local modname = name:gsub("%.lua$", ""):gsub("/", ".")
         table.insert(out, ("/* %s */"):format(modname))
         table.insert(out, ("{"))
         bin2c_file(out, filename)
         table.insert(out, ("luaL_loadbuffer(L, code, sizeof(code), %q);"):format(filename))
         table.insert(out, ("lua_setfield(L, 1, %q);"):format(modname))
         table.insert(out, ("}"))
      end
   end
   table.insert(out, [[
      lua_settop(L, 0);                                /* */
   }
   ]])
end

local function nm(filename)
   local pd = io.popen(NM .. " " .. filename)
   local out = pd:read("*a")
   pd:close()
   return out
end

local function declare_libraries(out, files)
   local a_files = {}
   local externs = {}
   local fn = {}
   table.insert(fn, [[
   static void declare_libraries(lua_State* L) {
      lua_getglobal(L, "package");                     /* package */
      lua_getfield(L, -1, "preload");                  /* package package.preload */
   ]])
   for _, filename in ipairs(files) do
      if filename:match("%.a$") then
         table.insert(a_files, filename)
         local nmout = nm(filename)
         for luaopen in nmout:gmatch("[^dD] _?(luaopen_[%a%p%d]+)") do

            -- FIXME what about module names with underscores?
            local modname = luaopen:gsub("^_?luaopen_", ""):gsub("_", ".")

            table.insert(externs, "extern int " .. luaopen .. "(lua_State* L);")
            table.insert(fn, "lua_pushcfunction(L, " .. luaopen .. ");")
            table.insert(fn, "lua_setfield(L, -2, \"" .. modname .. "\");")
         end
      end
   end
   table.insert(fn, [[
      lua_settop(L, 0);                                /* */
   }
   ]])

   table.insert(out, "\n")
   for _, line in ipairs(externs) do
      table.insert(out, line)
   end
   table.insert(out, "\n")
   for _, line in ipairs(fn) do
      table.insert(out, line)
   end
   table.insert(out, "\n")

   return a_files
end

-- main:

local c_program = arg[1]
local lua_program = arg[2]
local basename = arg[3]
for i = 1, 3 do table.remove(arg, 1) end
local modules = arg

local program_name = lua_program:gsub(".*/", "")

local out = {}
table.insert(out, ([[static const char* progname = %q;]]):format(program_name))
table.insert(out, c_preamble)
load_main(out, lua_program, program_name)
declare_modules(out, basename, modules)
declare_libraries(out, modules)
table.insert(out, c_main)

local fd = io.open(c_program, "w")
fd:write(reindent_c(table.concat(out, "\n")))
fd:close()

